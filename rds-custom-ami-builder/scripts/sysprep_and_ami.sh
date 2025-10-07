#!/usr/bin/env bash
# Sysprep Windows via SSM and create an AMI — with SSM/IAM preflight
# - If the instance has a PUBLIC IP, skip VPCE wiring (use Internet path)
# - If PRIVATE, ensure SSM Interface VPCEs and allow 443 from builder SG to VPCE SG
# - After AMI creation, revoke any VPCE ingress rules we added so 'terraform destroy' is clean
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for JSON encoding of SSM parameters. Install jq and re-run." >&2
  exit 1
fi

# ---------- inputs ----------
DEFAULT_REGION="$(aws configure get region 2>/dev/null)"
DEFAULT_REGION="${DEFAULT_REGION:-us-east-2}"
read -rp "AWS region [${DEFAULT_REGION}]: " REGION
REGION="${REGION:-$DEFAULT_REGION}"
if [[ -z "$REGION" ]]; then
  echo "Region is required (example: us-east-2)"; exit 1;
fi

read -rp "EC2 Instance ID (e.g., i-0123456789abcdef0): " INSTANCE_ID
if [[ -z "${INSTANCE_ID}" ]]; then echo "Instance ID is required"; exit 1; fi

STAMP="$(date +%Y%m%d-%H%M%S)"
read -rp "AMI name [ws2019-sql2022-dev-${STAMP}]: " AMI_NAME
AMI_NAME="${AMI_NAME:-ws2019-sql2022-dev-${STAMP}}"

# SQL Server 2022 Developer ISO location in S3 (used to install Dev before sysprep)
DEFAULT_SQL_ISO_URI="s3://dev-sqlserver-supportfiles-backups-and-iso-files/media/SQLServer2022-x64-ENU-Dev.iso"
read -rp "SQL Server 2022 Developer ISO S3 URI [${DEFAULT_SQL_ISO_URI}]: " SQL_ISO_URI
SQL_ISO_URI="${SQL_ISO_URI:-$DEFAULT_SQL_ISO_URI}"

# Allow override via env vars; otherwise use sane defaults
ROLE="${ROLE:-SSMManagedInstanceRole}"
PROFILE="${PROFILE:-SSMManagedInstanceProfile}"

# ---------- IAM preflight ----------
echo "== Preflight: ensuring SSM IAM role/profile are present =="
# Create role if missing
if ! aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  echo "Creating role: $ROLE"
  aws iam create-role --role-name "$ROLE" \
    --assume-role-policy-document '{
      "Version":"2012-10-17",
      "Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]
    }' >/dev/null
fi

# Attach core SSM policy (idempotent)
aws iam attach-role-policy \
  --role-name "$ROLE" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore >/dev/null 2>&1 || true

# Create instance profile if missing
if ! aws iam get-instance-profile --instance-profile-name "$PROFILE" >/dev/null 2>&1; then
  echo "Creating instance profile: $PROFILE"
  aws iam create-instance-profile --instance-profile-name "$PROFILE" >/dev/null
fi

# Add role to instance profile if not yet attached
ATTACHED="$(aws iam get-instance-profile --instance-profile-name "$PROFILE" \
  --query "InstanceProfile.Roles[?RoleName=='$ROLE'] | length(@)" --output text 2>/dev/null || echo 0)"
if [[ "$ATTACHED" != "1" ]]; then
  echo "Adding role $ROLE to profile $PROFILE"
  aws iam add-role-to-instance-profile \
    --instance-profile-name "$PROFILE" \
    --role-name "$ROLE" >/dev/null
fi

# Wait for IAM propagation and get profile ARN
echo "Waiting for IAM instance profile to propagate..."
for _ in {1..24}; do
  PROFILE_ARN="$(aws iam get-instance-profile --instance-profile-name "$PROFILE" \
    --query "InstanceProfile.Arn" --output text 2>/dev/null || true)"
  HAS_ROLE="$(aws iam get-instance-profile --instance-profile-name "$PROFILE" \
    --query "InstanceProfile.Roles[?RoleName=='$ROLE'] | length(@)" --output text 2>/dev/null || echo 0)"
  if [[ "$PROFILE_ARN" != "None" && "$PROFILE_ARN" != "null" && -n "$PROFILE_ARN" && "$HAS_ROLE" == "1" ]]; then
    break
  fi
  sleep 5
done
if [[ -z "${PROFILE_ARN:-}" || "$PROFILE_ARN" == "None" || "$PROFILE_ARN" == "null" ]]; then
  echo "Failed to obtain instance profile ARN. Aborting."
  exit 1
fi
echo "Profile ARN: $PROFILE_ARN"

# Associate or replace the instance's IAM instance profile
echo "Associating instance profile to $INSTANCE_ID (region $REGION)"
ASSOC_ID="$(aws ec2 describe-iam-instance-profile-associations --region "$REGION" \
  --filters "Name=instance-id,Values=$INSTANCE_ID" \
  --query "IamInstanceProfileAssociations[0].AssociationId" --output text 2>/dev/null || echo None)"
if [[ "$ASSOC_ID" == "None" || "$ASSOC_ID" == "null" ]]; then
  aws ec2 associate-iam-instance-profile --region "$REGION" \
    --instance-id "$INSTANCE_ID" \
    --iam-instance-profile Arn="$PROFILE_ARN" >/dev/null
else
  aws ec2 replace-iam-instance-profile-association --region "$REGION" \
    --association-id "$ASSOC_ID" \
    --iam-instance-profile Arn="$PROFILE_ARN" >/dev/null
fi

# ---------- network preflight (only if PRIVATE) ----------
# Discover instance subnet/VPC/SGs/public IP
SUBNET_ID=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].SubnetId" --output text)
VPC_ID=$(aws ec2 describe-subnets --region "$REGION" --subnet-ids "$SUBNET_ID" \
  --query "Subnets[0].VpcId" --output text)
read -r -a INSTANCE_SGS <<< "$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].SecurityGroups[*].GroupId" --output text)"
PUBLIC_IP=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

# vars to track what we add so we can clean up later
EP_SG=""

# Detect if VPC already has SSM VPCEs with Private DNS enabled
HAS_PRIV_DNS=0
for svc in ssm ssmmessages ec2messages; do
  PD=$(aws ec2 describe-vpc-endpoints --region "$REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" Name=service-name,Values="com.amazonaws.$REGION.$svc" \
    --query "length(VpcEndpoints[?PrivateDnsEnabled==\`true\`])" --output text 2>/dev/null || echo 0)
  if [[ "$PD" == "1" ]]; then HAS_PRIV_DNS=1; fi
done

if [[ -n "$PUBLIC_IP" && "$PUBLIC_IP" != "None" && "$PUBLIC_IP" != "null" && "$HAS_PRIV_DNS" == "0" ]]; then
  echo "== Instance has a PUBLIC IP ($PUBLIC_IP) and no Private-DNS VPCEs: using Internet path for SSM =="
else
  echo "== Using VPCE path for SSM (either instance is private OR Private-DNS VPCEs exist) =="

  # Reuse an existing VPCE SG if present (from SSM endpoint), else create one
  EP_SG=$(aws ec2 describe-vpc-endpoints --region "$REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" Name=service-name,Values="com.amazonaws.$REGION.ssm" \
    --query "VpcEndpoints[0].Groups[0].GroupId" --output text 2>/dev/null || echo "None")
  if [[ -z "$EP_SG" || "$EP_SG" == "None" || "$EP_SG" == "null" ]]; then
    EP_SG=$(aws ec2 create-security-group --region "$REGION" \
      --group-name "vpce-ssm-sg-$(date +%s)" \
      --description "SSM VPCE SG" --vpc-id "$VPC_ID" \
      --query GroupId --output text)
  fi

  # Allow HTTPS from the instance SGs to the VPCE SG (idempotent)
  for SG in "${INSTANCE_SGS[@]}"; do
    aws ec2 authorize-security-group-ingress --region "$REGION" \
      --group-id "$EP_SG" --protocol tcp --port 443 --source-group "$SG" >/dev/null 2>&1 || true
  done

  # Ensure the three SSM Interface VPCEs exist in this VPC and include the builder subnet
  for svc in ssm ssmmessages ec2messages; do
    EP_ID=$(aws ec2 describe-vpc-endpoints --region "$REGION" \
      --filters Name=vpc-id,Values="$VPC_ID" Name=service-name,Values="com.amazonaws.$REGION.$svc" \
      --query "VpcEndpoints[0].VpcEndpointId" --output text)

    if [[ -z "$EP_ID" || "$EP_ID" == "None" || "$EP_ID" == "null" ]]; then
      # Create the endpoint bound to this subnet and SG
      aws ec2 create-vpc-endpoint --region "$REGION" \
        --vpc-id "$VPC_ID" \
        --vpc-endpoint-type Interface \
        --service-name "com.amazonaws.$REGION.$svc" \
        --subnet-ids "$SUBNET_ID" \
        --security-group-ids "$EP_SG" \
        --private-dns-enabled >/dev/null || true
    else
      # Add the builder subnet to the existing endpoint (idempotent)
      aws ec2 modify-vpc-endpoint --region "$REGION" \
        --vpc-endpoint-id "$EP_ID" --add-subnet-ids "$SUBNET_ID" >/dev/null 2>&1 || true

      # Ensure the endpoint SG allows 443 from the instance SGs
      CUR_EP_SG=$(aws ec2 describe-vpc-endpoints --region "$REGION" --vpc-endpoint-ids "$EP_ID" \
        --query "VpcEndpoints[0].Groups[0].GroupId" --output text)
      EP_SG="${EP_SG:-$CUR_EP_SG}"
      for SG in "${INSTANCE_SGS[@]}"; do
        aws ec2 authorize-security-group-ingress --region "$REGION" \
          --group-id "$CUR_EP_SG" --protocol tcp --port 443 --source-group "$SG" >/dev/null 2>&1 || true
      done
    fi
  done

  # Give endpoints a moment to propagate
  sleep 30
fi

# ---------- SSM registration wait ----------
echo "Waiting for SSM to register the instance (up to ~2 min)..."
for _ in {1..24}; do
  COUNT="$(aws ssm describe-instance-information --region "$REGION" \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query "length(InstanceInformationList)" --output text 2>/dev/null || echo 0)"
  if [[ "$COUNT" == "1" ]]; then
    echo "✓ Instance is SSM-managed."
    break
  fi
  sleep 5
done
if [[ "${COUNT:-0}" != "1" ]]; then
  echo "Instance is not showing as SSM-managed. Check network/agent and try again. Aborting."
  exit 1
fi

 # ---------- S3 gateway endpoint (for private buckets via VPC policy) ----------
 # Ensure the builder subnet's route table has an S3 Gateway VPCE attached so bucket policies using aws:SourceVpc work.
 # This is idempotent; it reuses existing endpoint and attaches the correct RTB if needed.
 # Resolve the route table associated to the instance subnet; if none, fall back to the VPC's main route table.
 RTB_ID="$(aws ec2 describe-route-tables --region "$REGION" \
   --filters Name=association.subnet-id,Values="$SUBNET_ID" \
   --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null || true)"
 if [[ -z "$RTB_ID" || "$RTB_ID" == "None" || "$RTB_ID" == "null" ]]; then
   RTB_ID="$(aws ec2 describe-route-tables --region "$REGION" \
     --filters Name=vpc-id,Values="$VPC_ID" \
     --query 'RouteTables[?Associations[?Main==`true`]].RouteTableId | [0]' --output text 2>/dev/null || true)"
 fi
 if [[ -z "$RTB_ID" || "$RTB_ID" == "None" || "$RTB_ID" == "null" ]]; then
   RTB_ID="$(aws ec2 describe-route-tables --region "$REGION" \
     --filters Name=vpc-id,Values="$VPC_ID" \
     --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null || true)"
 fi
 echo "Using VPC=$VPC_ID RTB=$RTB_ID for S3 gateway endpoint wiring"
 if [[ -n "$RTB_ID" && "$RTB_ID" != "None" && "$RTB_ID" != "null" ]]; then
   S3_EP_ID="$(aws ec2 describe-vpc-endpoints --region "$REGION" \
     --filters Name=vpc-id,Values="$VPC_ID" Name=vpc-endpoint-type,Values=Gateway \
              Name=service-name,Values="com.amazonaws.$REGION.s3" \
     --query 'VpcEndpoints[0].VpcEndpointId' --output text 2>/dev/null || true)"
   if [[ -z "$S3_EP_ID" || "$S3_EP_ID" == "None" || "$S3_EP_ID" == "null" ]]; then
     echo "Creating S3 Gateway VPCE in $VPC_ID and attaching RTB $RTB_ID"
     S3_EP_ID="$(aws ec2 create-vpc-endpoint --region "$REGION" \
       --vpc-id "$VPC_ID" \
       --vpc-endpoint-type Gateway \
       --service-name "com.amazonaws.$REGION.s3" \
       --route-table-ids "$RTB_ID" \
       --query 'VpcEndpoint.VpcEndpointId' --output text 2>/dev/null || true)"
   else
     echo "Reusing S3 Gateway VPCE $S3_EP_ID; ensuring RTB $RTB_ID is attached"
     aws ec2 modify-vpc-endpoint --region "$REGION" \
       --vpc-endpoint-id "$S3_EP_ID" --add-route-table-ids "$RTB_ID" >/dev/null 2>&1 || true
   fi
   # Optional verification (non-fatal)
   aws ec2 describe-route-tables --region "$REGION" --route-table-ids "$RTB_ID" \
     --query 'RouteTables[0].Routes[?DestinationPrefixListId!=null]' --output text >/dev/null 2>&1 || true
 else
   echo "WARNING: Could not resolve a route table for subnet $SUBNET_ID; skipping S3 VPCE wiring."
 fi

# ---------- install SQL Server 2022 Developer (BYOM) ----------
echo "Installing SQL Server 2022 Developer from ${SQL_ISO_URI} ..."

# Parse bucket/key from the provided S3 URI
URI_NO_PREFIX="${SQL_ISO_URI#s3://}"
SQL_BUCKET="${URI_NO_PREFIX%%/*}"
SQL_KEY="${URI_NO_PREFIX#*/}"

POLICY_DOC="$(jq -n --arg b "$SQL_BUCKET" --arg k "$SQL_KEY" '{
    Version:"2012-10-17",
    Statement:[
      {Effect:"Allow", Action:["s3:ListBucket"], Resource:["arn:aws:s3:::\($b)"]},
      {Effect:"Allow", Action:["s3:GetObject","s3:GetObjectVersion"], Resource:["arn:aws:s3:::\($b)/\($k)"]},
      {Effect:"Allow", Action:["s3:PutObject"], Resource:["arn:aws:s3:::\($b)/logs/*"]}
    ]
  }')"
aws iam put-role-policy \
  --role-name "$ROLE" \
  --policy-name "AllowReadSQLISO" \
  --policy-document "$POLICY_DOC" >/dev/null

# Quick existence check for the object
if ! aws s3api head-object --bucket "$SQL_BUCKET" --key "$SQL_KEY" --region "$REGION" >/dev/null 2>&1; then
  echo "S3 object not found: s3://${SQL_BUCKET}/${SQL_KEY}" >&2
  exit 1
fi

# Also generate a short-lived presigned URL as a fallback path
SQL_ISO_PRESIGNED="$(aws s3 presign "s3://${SQL_BUCKET}/${SQL_KEY}" --region "${REGION}" --expires-in 21600)"

# BEGIN PATCHED BLOCK
PS_COMMAND=$(
  cat <<'POW'
$ErrorActionPreference="Stop"; $ProgressPreference="SilentlyContinue"; $PSNativeCommandUseErrorActionPreference=$true;
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item -ItemType Directory -Path C:\Temp -Force | Out-Null;
$iso = Join-Path $env:TEMP ("SQLDev_{0}.iso" -f ([guid]::NewGuid().ToString()));
$legacyIso = "C:\Temp\SQLDev.iso";

# Inputs injected by bash after this heredoc via placeholder substitution
$uS3    = "__S3_URI__";
$region = "__REGION__";

# Clean up any previous mount/file
Get-DiskImage -ImagePath $legacyIso -ErrorAction SilentlyContinue | Where-Object { $_.Attached } | Dismount-DiskImage -ErrorAction SilentlyContinue;
if (Test-Path $legacyIso) { Remove-Item $legacyIso -Force -ErrorAction SilentlyContinue }

# Ensure AWS CLI exists on the instance
if (-not (Get-Command aws.exe -ErrorAction SilentlyContinue)) {
  $msi = Join-Path $env:TEMP "awscli.msi";
  Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile $msi;
  $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn" -Wait -PassThru;
  if ($p.ExitCode -ne 0) { throw "AWS CLI install failed: $([int]$p.ExitCode)" }
}

# --- Prereqs: Ensure .NET Framework 4.7.2+ and VC++ 2015-2022 (x64) ---
function Get-DotNetRelease { try { (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full').Release } catch { 0 } }
$min472 = 461808  # .NET 4.7.2 minimum release key
$have = Get-DotNetRelease
if ($have -lt $min472) {
  Write-Host "[BYOM] Installing .NET Framework 4.8 ..."
  $dotUrl = "https://go.microsoft.com/fwlink/?linkid=2088631"  # ndp48-x86-x64-allos-enu.exe
  $dotExe = Join-Path $env:TEMP "ndp48-x86-x64-allos-enu.exe"
  try { Start-BitsTransfer -Source $dotUrl -Destination $dotExe -Priority Foreground -ErrorAction Stop }
  catch { Invoke-WebRequest -Uri $dotUrl -OutFile $dotExe -UseBasicParsing -TimeoutSec 1800 }
  $dp = Start-Process -FilePath $dotExe -ArgumentList "/q /norestart" -Wait -PassThru
  if ($dp.ExitCode -ne 0 -and $dp.ExitCode -ne 3010) { throw "DotNet48 install failed with exit code $($dp.ExitCode)" }
}

Write-Host "[BYOM] Ensuring VC++ 2015-2022 (x64) redistributable ..."
$vcUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
$vcExe = Join-Path $env:TEMP "vc_redist.x64.exe"
try { Start-BitsTransfer -Source $vcUrl -Destination $vcExe -Priority Foreground -ErrorAction Stop }
catch { Invoke-WebRequest -Uri $vcUrl -OutFile $vcExe -UseBasicParsing -TimeoutSec 1800 }
$vp = Start-Process -FilePath $vcExe -ArgumentList "/quiet /norestart" -Wait -PassThru
if ($vp.ExitCode -ne 0 -and $vp.ExitCode -ne 3010) { throw "VC++ Redist install failed with exit code $($vp.ExitCode)" }
# --- End prereqs ---

# Try IAM-authenticated copy first (PS 5.1 compatible)
$copied = $false
$awsCmd = Get-Command aws.exe -ErrorAction SilentlyContinue
$aws = $null
if ($awsCmd) { $aws = $awsCmd.Source }
if (-not $aws) { $aws = Join-Path $env:ProgramFiles "Amazon\AWSCLIV2\aws.exe" }
try {
  & "$aws" s3 cp $uS3 $iso --region $region --no-progress
  if (Test-Path $iso) {
    $copied = $true
    Write-Host "[BYOM] Downloaded ISO via aws s3 cp (IAM auth)."
  }
} catch {
  Write-Warning ("[BYOM] aws s3 cp threw: {0}" -f $_.Exception.Message)
}

# Fallback to presigned URL only if IAM path failed
if (-not $copied) {
  Write-Warning "[BYOM] Falling back to presigned URL. First try BITS, then Invoke-WebRequest."
  $u = "__PRESIGNED__"
  $max = 5
  for ($i=1; $i -le $max; $i++) {
    try {
      Start-BitsTransfer -Source $u -Destination $iso -Description "SQLDevISO" -Priority Foreground -ErrorAction Stop
      if (Test-Path $iso) { $copied = $true; break }
    } catch {
      if ($i -lt $max) { Start-Sleep -Seconds ([math]::Pow(2,$i)) }
      else { Write-Warning ("[BYOM] BITS failed on final attempt: {0}" -f $_.Exception.Message) }
    }
  }
  if (-not $copied) {
    try {
      Invoke-WebRequest -Uri $u -OutFile $iso -UseBasicParsing -TimeoutSec 7200
      if (Test-Path $iso) { $copied = $true; Write-Host "[BYOM] Downloaded ISO via Invoke-WebRequest." }
      else { throw "Invoke-WebRequest completed but file not found at $iso" }
    } catch { throw ("Presigned URL download failed. Last error: {0}" -f $_.Exception.Message) }
  }
}

# Mount, install, unmount
$img = Mount-DiskImage -ImagePath $iso -PassThru;
Start-Sleep -Seconds 5;
$dl = (Get-Volume -DiskImage $img).DriveLetter;
$setup = "$($dl):\setup.exe";
$args = "/Q /ACTION=Install /FEATURES=SQLENGINE /INSTANCENAME=MSSQLSERVER /IACCEPTSQLSERVERLICENSETERMS /SQLSYSADMINACCOUNTS=`"NT AUTHORITY\\SYSTEM`" /SQLSVCSTARTUPTYPE=Manual /AGTSVCSTARTUPTYPE=Manual /BROWSERSVCSTARTUPTYPE=Disabled /UPDATEENABLED=0 /INDICATEPROGRESS"
$p = Start-Process -FilePath $setup -ArgumentList $args -Wait -PassThru;

# Prepare to capture logs if setup fails
$logRootCandidates = @(
  "C:\\Program Files\\Microsoft SQL Server\\160\\Setup Bootstrap\\Log",
  "C:\\Program Files\\Microsoft SQL Server\\150\\Setup Bootstrap\\Log"
)
$logRoot = $null
foreach ($c in $logRootCandidates) { if (Test-Path $c) { $logRoot = $c; break } }

if ($p.ExitCode -ne 0) {
  try {
    $latest = if ($logRoot) { Get-ChildItem -Path $logRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1 } else { $null }
    $zip = Join-Path $env:TEMP ("SQLSetupLogs_{0}.zip" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    if ($latest -and (Test-Path $latest.FullName)) {
      Compress-Archive -Path $latest.FullName -DestinationPath $zip -Force -ErrorAction SilentlyContinue | Out-Null
    }

    # Derive bucket from the S3 URI and upload logs under logs/sqlsetup/
    $bucket = $null
    if ($uS3 -match '^s3://([^/]+)/') { $bucket = $matches[1] }
    if ($bucket -and (Test-Path $zip)) {
      $destKey = "logs/sqlsetup/$($env:COMPUTERNAME)_$((Get-Date).ToString('yyyyMMdd_HHmmss')).zip"
      & "$aws" s3 cp $zip ("s3://{0}/{1}" -f $bucket, $destKey) --region $region --no-progress | Out-Null
      Write-Warning ("[BYOM] SQL setup failed. Logs uploaded to s3://{0}/{1}" -f $bucket, $destKey)
    } else {
      Write-Warning "[BYOM] SQL setup failed and logs zip could not be uploaded (missing bucket or zip)."
    }
  } catch {
    Write-Warning ("[BYOM] Failed to package/upload SQL setup logs: {0}" -f $_.Exception.Message)
  }
  throw "SQL Setup failed with exit code $([int]$p.ExitCode)"
}

Dismount-DiskImage -ImagePath $iso -ErrorAction SilentlyContinue;
Remove-Item $iso -Force -ErrorAction SilentlyContinue

Write-Host "[BYOM] Stopping SQL services before sysprep..."
Stop-Service SQLSERVERAGENT -Force -ErrorAction SilentlyContinue
Stop-Service MSSQLSERVER -Force
Stop-Service SQLBrowser -ErrorAction SilentlyContinue

Set-Service MSSQLSERVER -StartupType Manual
Set-Service SQLSERVERAGENT -StartupType Manual
Set-Service SQLBrowser -StartupType Disabled -ErrorAction SilentlyContinue

POW
)
# Inject the bash variables into the PowerShell script safely
PS_COMMAND="${PS_COMMAND//__S3_URI__/s3://${SQL_BUCKET}/${SQL_KEY}}"
PS_COMMAND="${PS_COMMAND//__REGION__/$REGION}"
PS_COMMAND="${PS_COMMAND//__PRESIGNED__/$SQL_ISO_PRESIGNED}"
# END PATCHED BLOCK

# Build JSON parameters safely to avoid shell/quote parsing issues
PARAMS_JSON="$(jq -n --arg c "$PS_COMMAND" '{commands: [$c]}')"

CMD_ID="$(aws ssm send-command \
  --region "${REGION}" \
  --instance-ids "${INSTANCE_ID}" \
  --document-name "AWS-RunPowerShellScript" \
  --comment "Install SQL Server 2022 Developer (BYOM)" \
  --cli-binary-format raw-in-base64-out \
  --parameters "$PARAMS_JSON" \
  --query 'Command.CommandId' --output text)"

echo "Waiting for SQL Server install to finish..."
for _ in {1..120}; do
  STATUS="$(aws ssm list-command-invocations --region "${REGION}" --command-id "$CMD_ID" --details \
    --query 'CommandInvocations[0].Status' --output text 2>/dev/null || echo "Pending")"
  if [[ "$STATUS" == "Success" ]]; then echo "✓ SQL Server Developer installed."; break; fi
  if [[ "$STATUS" == "Failed" || "$STATUS" == "Cancelled" || "$STATUS" == "TimedOut" ]]; then
    echo "SQL install status: $STATUS"
    echo "Fetching invocation output..."
    INV_JSON="$(aws ssm get-command-invocation \
      --region "${REGION}" \
      --command-id "$CMD_ID" \
      --instance-id "${INSTANCE_ID}" \
      --output json 2>/dev/null || true)"
    if [[ -n "$INV_JSON" && "$INV_JSON" != "null" ]]; then
      echo "----- SSM STDOUT (tail) -----"
      echo "$INV_JSON" | jq -r '.StandardOutputContent' | tail -n 200
      echo "----- SSM STDERR (tail) -----"
      echo "$INV_JSON" | jq -r '.StandardErrorContent' | tail -n 200
    fi
    exit 1
  fi
  sleep 15
done

# ---------- sysprep via Automation runbook or Run Command ----------
echo "Checking for AWSEC2-RunSysprep runbook in ${REGION}..."
HAS_RB="$(aws ssm list-documents --region "${REGION}" \
  --filters Key=Name,Values=AWSEC2-RunSysprep \
  --output text --query 'DocumentIdentifiers[0].Name' 2>/dev/null || true)"

if [[ "${HAS_RB}" == "AWSEC2-RunSysprep" ]]; then
  echo "Starting Automation: AWSEC2-RunSysprep (2h timeout)"
  aws ssm start-automation-execution \
    --region "${REGION}" \
    --document-name "AWSEC2-RunSysprep" \
    --parameters "{\"InstanceId\":[\"${INSTANCE_ID}\"],\"SysprepTimeout\":[\"16000000\"]}" >/dev/null
else
  echo "Runbook not found. Falling back to Run Command (AWS-RunPowerShellScript)."
  aws ssm send-command \
    --region "${REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --document-name "AWS-RunPowerShellScript" \
    --parameters commands="C:\\Windows\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /shutdown" \
    --cloud-watch-output-config CloudWatchOutputEnabled=true >/dev/null
fi

echo "Waiting for instance to stop after Sysprep..."
aws ec2 wait instance-stopped --region "${REGION}" --instance-ids "${INSTANCE_ID}"

# ---------- create AMI ----------
echo "Creating AMI: ${AMI_NAME}"
AMI_ID="$(aws ec2 create-image \
  --region "${REGION}" \
  --instance-id "${INSTANCE_ID}" \
  --name "${AMI_NAME}" \
  --description "WS2019 + SQL 2022 (Developer) sysprepped" \
  --output text --query ImageId)"
echo "AMI: ${AMI_ID}"

echo "Waiting for AMI to become available..."
aws ec2 wait image-available --region "${REGION}" --image-ids "${AMI_ID}"
echo "Success. AMI ready: ${AMI_ID}"

# ---------- cleanup VPCE ingress rule so 'terraform destroy' is clean ----------
if [[ -n "${EP_SG:-}" ]]; then
  echo "Cleaning up VPCE ingress (revoke 443 from VPCE SG -> builder SGs) ..."
  # Revoke only the SG rules we might have added above; safe if they didn't exist
  for SG in "${INSTANCE_SGS[@]}"; do
    aws ec2 revoke-security-group-ingress --region "$REGION" \
      --group-id "$EP_SG" --protocol tcp --port 443 --source-group "$SG" >/dev/null 2>&1 || true
  done
  echo "✓ VPCE ingress cleaned (endpoints left intact)."
fi
