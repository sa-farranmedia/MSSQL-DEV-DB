#!/bin/bash
set -e

echo "=========================================="
echo "Create Custom Engine Version (CEV)"
echo "=========================================="

# Prompt for AMI ID
read -p "Enter AMI ID (e.g., ami-0123456789abcdef0): " AMI_ID

if [ -z "$AMI_ID" ]; then
    echo "ERROR: AMI ID is required"
    exit 1
fi

# Generate CEV version with date
CEV_DATE=$(date +%Y%m%d)
CEV_VERSION="16.00.4210.1.dev-cev-${CEV_DATE}"

echo ""
echo "CEV Version: $CEV_VERSION"
echo "AMI ID: $AMI_ID"
echo "Engine: custom-sqlserver-ee"
echo "Region: us-east-2"
echo ""
read -p "Create Custom Engine Version? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled"
    exit 0
fi

echo ""
echo "Creating Custom Engine Version..."

# Create CEV
aws rds create-custom-db-engine-version \
  --engine custom-sqlserver-ee \
  --engine-version "$CEV_VERSION" \
  --database-installation-files-s3-bucket-name "dev-sqlserver-supportfiles-backups-and-iso-files" \
  --database-installation-files-s3-prefix "media/" \
  --image-id "$AMI_ID" \
  --region us-east-2

echo ""
echo "=========================================="
echo "✓ CEV creation initiated!"
echo "=========================================="
echo "CEV Version: $CEV_VERSION"
echo ""
echo "Check CEV status with:"
echo "aws rds describe-db-engine-versions \\"
echo "  --engine custom-sqlserver-ee \\"
echo "  --engine-version $CEV_VERSION \\"
echo "  --region us-east-2"
echo ""
echo "CEV must show status 'available' before use"
echo "(This typically takes 20-30 minutes)"
echo ""
echo "Next steps:"
echo "1. Wait for CEV status to be 'available'"
echo "2. Update terraform/modules/rds_custom_dev/main.tf"
echo "3. Uncomment aws_db_instance.rds_custom resource"
echo "4. Set engine_version = \"$CEV_VERSION\""
echo "5. Set enable_rds_custom = true in dev.tfvars"
echo "6. Run: terraform apply"
echo "=========================================="


