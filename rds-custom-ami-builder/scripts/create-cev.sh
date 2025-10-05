#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "Create Custom Engine Version (CEV)"
echo "=========================================="

# Prompt for AMI ID
read -rp "Enter AMI ID (e.g., ami-0123456789abcdef0): " AMI_ID
if [[ -z "${AMI_ID}" ]]; then
  echo "ERROR: AMI ID is required"; exit 1
fi

# Region (use current CLI default if present)
REGION="${REGION:-$(aws configure get region 2>/dev/null || echo us-east-2)}"

# Resolve AMI metadata (name helps infer SQL edition and OS)
AMI_NAME=$(aws ec2 describe-images --region "$REGION" --image-ids "$AMI_ID" \
  --query 'Images[0].Name' --output text 2>/dev/null || echo "Unknown")

# Infer engine from AMI name; fallback to prompt if unrecognized
ENGINE=""
EDITION=""
case "$AMI_NAME" in
  *SQL_2022_Web*|*SQL_2019_Web*)          ENGINE="custom-sqlserver-we"; EDITION="Web" ;;
  *SQL_2022_Standard*|*SQL_2019_Standard*)ENGINE="custom-sqlserver-se"; EDITION="Standard" ;;
  *SQL_2022_Enterprise*|*SQL_2019_Enterprise*) ENGINE="custom-sqlserver-ee"; EDITION="Enterprise" ;;
  *)
    echo "Could not infer SQL edition from AMI name: $AMI_NAME"
    read -rp "Enter engine (custom-sqlserver-we | custom-sqlserver-se | custom-sqlserver-ee): " ENGINE
    case "$ENGINE" in
      custom-sqlserver-we) EDITION="Web" ;;
      custom-sqlserver-se) EDITION="Standard" ;;
      custom-sqlserver-ee) EDITION="Enterprise" ;;
      *) echo "ERROR: Invalid engine selection"; exit 1 ;;
    esac
  ;;
 esac

# Warn if not WS2019 (RDS Custom CEV requires Windows Server 2019)
if [[ "$AMI_NAME" != *"Windows_Server-2019"* ]]; then
  echo "WARNING: AMI name does not indicate Windows_Server-2019: $AMI_NAME"
  read -rp "Continue anyway? (yes/no): " CONT
  [[ "$CONT" == "yes" ]] || exit 1
fi

# Generate CEV version (SQL 2022 CU19 build number)
STAMP=$(date +%Y%m%d)
CEV_VERSION=${CEV_VERSION:-"16.00.4195.2.dev-cev-${STAMP}"}

# If a CEV with same version already exists for this engine, stop early
EXISTS=$(aws rds describe-db-engine-versions --region "$REGION" \
  --engine "$ENGINE" --engine-version "$CEV_VERSION" \
  --query 'length(DBEngineVersions)' --output text 2>/dev/null || echo 0)
if [[ "$EXISTS" == "1" ]]; then
  echo "ERROR: A CEV with engine=$ENGINE and version=$CEV_VERSION already exists in $REGION."; exit 1
fi

echo ""
echo "CEV Version: $CEV_VERSION"
echo "AMI ID: $AMI_ID"
echo "AMI Name: $AMI_NAME"
echo "Engine: $ENGINE ($EDITION)"
echo "Region: $REGION"
echo ""
read -rp "Create Custom Engine Version? (yes/no): " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { echo "Cancelled"; exit 0; }

echo ""
echo "Creating Custom Engine Version..."
aws rds create-custom-db-engine-version \
  --region "$REGION" \
  --engine "$ENGINE" \
  --engine-version "$CEV_VERSION" \
  --image-id "$AMI_ID" \
  --description "Custom SQL Server 2022 ${EDITION} LI (CU19)"

cat <<EOF

==========================================
✓ CEV creation initiated!
==========================================
CEV Version: $CEV_VERSION

Check CEV status with:
  aws rds describe-db-engine-versions \
    --engine $ENGINE \
    --engine-version $CEV_VERSION \
    --region $REGION

IMPORTANT:
  A CEV remains 'pending-validation' until you successfully create an RDS Custom DB from it.
  The DB create run performs validation; after it succeeds, the CEV flips to 'available'.

Next steps:
  1) Ensure your DB subnets can reach required services (ssm, ssmmessages, ec2messages, logs, monitoring, events, secretsmanager, and S3).
  2) Create a DB instance from this CEV (Terraform or CLI) to perform validation.
  3) Point Terraform engine/version to: $ENGINE / $CEV_VERSION
EOF
