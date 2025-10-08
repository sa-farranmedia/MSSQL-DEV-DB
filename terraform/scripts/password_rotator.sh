#!/bin/zsh
set -euo pipefail

# Debug + optional KMS for Secrets Manager
DEBUG=${DEBUG:-1}
KMS_KEY_ID="${KMS_KEY_ID:-}"
if [[ "${DEBUG}" == "1" ]]; then
  set -x
  trap 'echo "ERR at line $LINENO"' ERR
fi

REGION=${REGION:-us-east-2}
DBID="dev-legacy-webapp-rds-custom"
LOGIN="sqladmin"
SECRET_NAME="${DBID}-master"

# discover the RDS Custom host EC2 instance
DBRID=$(aws rds describe-db-instances \
  --region "$REGION" --db-instance-identifier "$DBID" \
  --query 'DBInstances[0].DbiResourceId' --output text)

EC2ID=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=tag:Name,Values=$DBRID" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

if [[ -z "$EC2ID" || "$EC2ID" == "None" ]]; then
  # Fallback: try to find an instance using the RDS Custom instance profile and common Name patterns
  EC2ID=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=iam-instance-profile.arn,Values=*AWSRDSCustom*" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[?Tags[?Key==`Name` && (contains(Value, `do-not-delete`) || contains(Value, `rds`) || contains(Value, `'"$DBRID"'`))]].InstanceId' \
    --output text | awk 'NF{print; exit}')
fi
[[ -z "$EC2ID" || "$EC2ID" == "None" ]] && { echo "could not resolve EC2 for $DBID ($DBRID)"; exit 1; }

echo "DB ResourceId: $DBRID"
echo "EC2 InstanceId: $EC2ID"
echo "Sanity checks & deps..."
command -v aws >/dev/null || { echo "ERROR: aws CLI not installed"; exit 1; }
command -v jq  >/dev/null || { echo "ERROR: jq not installed"; exit 1; }
command -v base64 >/dev/null || { echo "ERROR: base64 not found"; exit 1; }

 # generate a strong password (no single quotes to keep T-SQL quoting simple)
NEWPW=$(python3 - <<'PY'
import secrets, string
alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#%^*_+=-'
print(''.join(secrets.choice(alphabet) for _ in range(32)))
PY
)
[[ ${#NEWPW} -eq 32 ]] || { echo "ERROR: failed to generate password"; exit 1; }

# build the PowerShell script safely (no shell expansion inside)
echo "Building PowerShell payload..."
PRE_PS="$(mktemp)"
cat >"$PRE_PS" <<'PSEOF'
$ErrorActionPreference='Stop'
[void][System.Reflection.Assembly]::LoadWithPartialName('System.Data')

# Ensure SQL service is running
$svc='MSSQLSERVER'
try { if ((Get-Service $svc).Status -ne 'Running') { Start-Service $svc; Start-Sleep -Seconds 5 } } catch {}

$login = '__LOGIN__'
$pw_b64 = '__PW_B64__'
$pw = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($pw_b64))

# Candidate sqlcmd paths (if client tools are present)
$sqlcmdPaths = @(
  'C:\\Program Files\\Microsoft SQL Server\\Client SDK\\ODBC\\170\\Tools\\Binn\\sqlcmd.exe',
  'C:\\Program Files\\Microsoft SQL Server\\160\\Tools\\Binn\\sqlcmd.exe'
) | Where-Object { Test-Path $_ }

function Invoke-WithSqlClient {
  param([string]$Query,[hashtable]$Params)
  $cs = 'Server=localhost;Database=master;Integrated Security=True;TrustServerCertificate=True;Connection Timeout=15'
  $con = New-Object System.Data.SqlClient.SqlConnection $cs
  $con.Open()
  $cmd = $con.CreateCommand()
  $cmd.CommandText = $Query
  if ($Params) {
    foreach ($k in $Params.Keys) {
      $p = $cmd.Parameters.Add($k,[System.Data.SqlDbType]::VarChar,256)
      $p.Value = $Params[$k]
    }
  }
  $null = $cmd.ExecuteNonQuery()
  $con.Close()
}

# Quick permissions probe under Windows auth
try {
  Invoke-WithSqlClient "SELECT 1" $null
} catch {
  throw "Windows auth test failed: $($_.Exception.Message)"
}

# Attempt ALTER LOGIN using SqlClient only (escape quotes; parameters not supported here)
try {
  $esc = $pw -replace '''',''''''
  $tsql = "ALTER LOGIN [$login] WITH PASSWORD = '$esc';"
  Invoke-WithSqlClient $tsql $null
  Write-Host "Password updated for $login using SqlClient"
} catch {
  throw "ALTER LOGIN failed: $($_.Exception.Message)"
}
PSEOF

# fill placeholders without breaking quoting; use base64 for password literal
PW_B64="$(printf '%s' "$NEWPW" | base64 | tr -d '\n')"
PRE_PS_FILLED="$(mktemp)"
sed -e "s|__LOGIN__|$LOGIN|g" \
    -e "s|__PW_B64__|$PW_B64|g" "$PRE_PS" > "$PRE_PS_FILLED"

# wrap into SSM parameters JSON
PARAMS_FILE="$(mktemp -t ssm.XXXX.json)"
jq -Rs '{commands: [.]}' "$PRE_PS_FILLED" > "$PARAMS_FILE"
echo "Params file: $PARAMS_FILE"

echo "Resetting password for login '$LOGIN' on EC2 $EC2ID via SSM..."

CMDID=$(aws ssm send-command \
  --region "$REGION" \
  --document-name "AWS-RunPowerShellScript" \
  --instance-ids "$EC2ID" \
  --parameters file://"$PARAMS_FILE" \
  --query 'Command.CommandId' --output text)
echo "SSM CommandId: $CMDID"
[[ -z "$CMDID" || "$CMDID" == "None" ]] && { echo "Failed to send SSM command"; exit 1; }

# wait for completion (simple poll)
for i in {1..60}; do
  st=$(aws ssm get-command-invocation --region "$REGION" \
        --command-id "$CMDID" --instance-id "$EC2ID" \
        --query 'Status' --output text 2>/dev/null || echo "Pending")
  [[ "$st" == "Success" ]] && break
  if [[ "$st" == "Failed" || "$st" == "Cancelled" || "$st" == "TimedOut" ]]; then
    echo "SSM command $st — fetching output:";
    aws ssm get-command-invocation --region "$REGION" \
      --command-id "$CMDID" --instance-id "$EC2ID" \
      --query '[StandardOutputContent,StandardErrorContent]' --output text || true
    exit 1
  fi
  sleep 5
done

# show SSM output for visibility
aws ssm get-command-invocation --region "$REGION" \
  --command-id "$CMDID" --instance-id "$EC2ID" \
  --query '[StandardOutputContent,StandardErrorContent]' --output text || true

# store/update the secret (create if missing, otherwise put new version)
if ! aws secretsmanager describe-secret --region "$REGION" --secret-id "$SECRET_NAME" >/dev/null 2>&1; then
  echo "Creating secret $SECRET_NAME (KMS: ${KMS_KEY_ID:-aws/secretsmanager})"
  if [[ -n "$KMS_KEY_ID" ]]; then
    aws secretsmanager create-secret --region "$REGION" \
      --name "$SECRET_NAME" \
      --kms-key-id "$KMS_KEY_ID" \
      --secret-string "$(jq -n --arg u "$LOGIN" --arg p "$NEWPW" '{username:$u,password:$p}')"
  else
    aws secretsmanager create-secret --region "$REGION" \
      --name "$SECRET_NAME" \
      --secret-string "$(jq -n --arg u "$LOGIN" --arg p "$NEWPW" '{username:$u,password:$p}')"
  fi
else
  echo "Updating secret $SECRET_NAME"
  aws secretsmanager put-secret-value --region "$REGION" \
    --secret-id "$SECRET_NAME" \
    --secret-string "$(jq -n --arg u "$LOGIN" --arg p "$NEWPW" '{username:$u,password:$p}')"
fi

echo "username: $LOGIN"
echo "password: $NEWPW"
echo "secret:   $SECRET_NAME"
echo "note: password has been written to Secrets Manager as JSON {username,password}"