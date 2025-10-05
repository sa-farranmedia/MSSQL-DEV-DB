#!/bin/bash
set -e

echo "=========================================="
echo "Deploy RDS Custom Instance"
echo "=========================================="

# Prompt for CEV version
read -p "Enter CEV version (e.g., 16.00.4195.2.dev-cev-20250103): " CEV_VERSION

if [ -z "$CEV_VERSION" ]; then
    echo "ERROR: CEV version is required"
    exit 1
fi

echo ""
echo "Checking CEV status..."

# Check if CEV exists and is available
CEV_STATUS=$(aws rds describe-db-engine-versions \
  --engine custom-sqlserver-we \
  --engine-version "$CEV_VERSION" \
  --region us-east-2 \
  --query 'DBEngineVersions[0].Status' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$CEV_STATUS" == "NOT_FOUND" ] || [ -z "$CEV_STATUS" ]; then
    echo "ERROR: CEV $CEV_VERSION not found"
    echo "Ensure CEV has been created with create-cev.sh"
    exit 1
fi

if [ "$CEV_STATUS" != "available" ]; then
    echo "ERROR: CEV status is '$CEV_STATUS', not 'available'"
    echo "Wait for CEV to be available before deploying RDS Custom"
    exit 1
fi

echo "✓ CEV is available"
echo ""

# Navigate to main Terraform directory
cd ../../terraform

echo "=========================================="
echo "Manual Configuration Required"
echo "=========================================="
echo ""
echo "Before running terraform apply, you must:"
echo ""
echo "1. Edit: terraform/modules/rds_custom_dev/main.tf"
echo "   - Uncomment the 'aws_db_instance.rds_custom' resource"
echo "   - Update engine_version to: $CEV_VERSION"
echo ""
echo "2. Edit: terraform/modules/rds_custom_dev/outputs.tf"
echo "   - Uncomment the real output blocks"
echo "   - Comment out placeholder outputs"
echo ""
echo "3. Edit: terraform/envs/dev/dev.tfvars"
echo "   - Set: enable_rds_custom = true"
echo ""
echo "4. Run Terraform:"
echo "   terraform init -backend-config=envs/dev/backend.hcl"
echo "   terraform apply -var-file=envs/dev/dev.tfvars"
echo ""
echo "=========================================="
echo ""
read -p "Have you completed these steps? (yes/no): " READY

if [ "$READY" != "yes" ]; then
    echo ""
    echo "Complete the manual steps above, then re-run this script"
    exit 0
fi

echo ""
echo "Running terraform apply..."
echo ""

terraform init -backend-config=envs/dev/backend.hcl
terraform apply -var-file=envs/dev/dev.tfvars

echo ""
echo "=========================================="
echo "✓ RDS Custom deployment complete!"
echo "=========================================="