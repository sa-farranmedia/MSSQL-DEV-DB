#!/bin/bash
# Deploy RDS Custom SQL Server instance using the created CEV

set -e

# Configuration
REGION=${AWS_REGION:-us-east-2}
PROJECT_NAME="legacy-wepabb"
ENV="dev"

# Load CEV info
if [ ! -f "../cev-info.txt" ]; then
    echo "ERROR: CEV info file not found"
    echo "Run create-cev.sh first"
    exit 1
fi

source ../cev-info.txt

echo "=========================================="
echo "Deploying RDS Custom SQL Server Instance"
echo "=========================================="
echo "Engine: $ENGINE"
echo "Engine Version: $ENGINE_VERSION"
echo "Region: $REGION"
echo ""

# Go back to main terraform directory
cd ../../terraform

echo "Updating Terraform configuration..."
echo "Setting enable_rds_custom=true and rds_custom_engine_version=$ENGINE_VERSION"
echo ""

# Apply Terraform with RDS Custom enabled
terraform apply \
  -var="enable_rds_custom=true" \
  -var="rds_custom_engine_version=$ENGINE_VERSION" \
  -var-file=envs/dev/dev.tfvars \
  -auto-approve

echo ""
echo "=========================================="
echo "RDS Custom Instance Deployment Complete!"
echo "=========================================="
echo ""
echo "Get RDS endpoint:"
echo "  terraform output rds_endpoint"
echo ""
echo "Connect via SSM port forwarding:"
echo "  aws ssm start-session \\"
echo "    --target \$(terraform output -raw instance_id) \\"
echo "    --region $REGION \\"
echo "    --document-name AWS-StartPortForwardingSessionToRemoteHost \\"
echo "    --parameters '{\"portNumber\":[\"1433\"],\"localPortNumber\":[\"11433\"],\"host\":[\"\$(terraform output -raw rds_endpoint)\"]}'"
echo ""
