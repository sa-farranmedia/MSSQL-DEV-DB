#!/usr/bin/env bash
# Sysprep Windows via SSM and create an AMI — with SSM/IAM preflight
# - If the instance has a PUBLIC IP, skip VPCE wiring (use Internet path)
# - If PRIVATE, ensure SSM Interface VPCEs and allow 443 from builder SG to VPCE SG
# - After AMI creation, revoke any VPCE ingress rules we added so 'terraform destroy' is clean
set -euo pipefail

# ---------- inputs ----------
DEFAULT_REGION="$(aws configure get region 2>/dev/null || echo us-east-2)"
read -rp "AWS region [${DEFAULT_REGION}]: " REGION
REGION="${REGION:-$DEFAULT_REGION}"

read -rp "EC2 Instance ID (e.g., i-0123456789abcdef0): " INSTANCE_ID
if [[ -z "${INSTANCE_ID}" ]]; then echo "Instance ID is required"; exit 1; fi

STAMP="$(date +%Y%m%d-%H%M%S)"
read -rp "AMI name [ws2019-sql2022-li-${STAMP}]: " AMI_NAME
AMI_NAME="${AMI_NAME:-ws2019-sql2022-li-${STAMP}}"

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
    --parameters "{\"InstanceId\":[\"${INSTANCE_ID}\"],\"SysprepTimeout\":[\"7200000\"]}" >/dev/null
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
  --description "WS2019 + SQL 2022 (LI) sysprepped" \
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
