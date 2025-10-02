#!/bin/bash
# Create Custom Engine Version (CEV) for RDS Custom SQL Server

set -e

# Configuration
REGION=${AWS_REGION:-us-east-2}
PROJECT_NAME="legacy-wepabb"
ENV="dev"

# AMI ID (pass as argument or read from file)
if [ -n "$1" ]; then
    AMI_ID="$1"
elif [ -f "../ami-id.txt" ]; then
    AMI_ID=$(cat ../ami-id.txt)
else
    echo "ERROR: No AMI ID provided"
    echo "Usage: ./create-cev.sh <ami-id>"
    echo "Or run create-ami.sh first to save AMI ID"
    exit 1
fi

# CEV Configuration
ENGINE="custom-sqlserver-ee"
ENGINE_VERSION="15.00.4335.1.${ENV}-cev-$(date +%Y%m%d)"
CEV_NAME="${ENV}-${PROJECT_NAME}-sqlserver-cev"

echo "=========================================="
echo "Creating Custom Engine Version (CEV)"
echo "=========================================="
echo "Engine: $ENGINE"
echo "Engine Version: $ENGINE_VERSION"
echo "AMI ID: $AMI_ID"
echo "Region: $REGION"
echo ""

# Note: RDS Custom CEV creation requires specific S3 bucket setup
# This is a simplified version - you may need additional configuration

echo "Creating CEV..."
echo "NOTE: This requires proper S3 bucket setup for CEV files."
echo "If this fails, you may need to:"
echo "  1. Create S3 bucket: ${PROJECT_NAME}-cev-files"
echo "  2. Enable versioning on the bucket"
echo "  3. Prepare CEV manifest files"
echo ""

# Uncomment and customize this command once S3 bucket is ready
# aws rds create-custom-db-engine-version \
#   --engine $ENGINE \
#   --engine-version $ENGINE_VERSION \
#   --database-installation-files-s3-bucket-name "${PROJECT_NAME}-cev-files" \
#   --image-id $AMI_ID \
#   --manifest file://cev-manifest.json \
#   --region $REGION \
#   --tags "Key=Name,Value=$CEV_NAME" "Key=Project,Value=$PROJECT_NAME" "Key=Environment,Value=$ENV"

echo ""
echo "=========================================="
echo "CEV Creation Commands"
echo "=========================================="
echo "Run these commands after setting up CEV S3 bucket:"
echo ""
echo "aws rds create-custom-db-engine-version \\"
echo "  --engine $ENGINE \\"
echo "  --engine-version $ENGINE_VERSION \\"
echo "  --database-installation-files-s3-bucket-name ${PROJECT_NAME}-cev-files \\"
echo "  --image-id $AMI_ID \\"
echo "  --region $REGION"
echo ""
echo "Check CEV status:"
echo "aws rds describe-db-engine-versions \\"
echo "  --engine $ENGINE \\"
echo "  --engine-version $ENGINE_VERSION \\"
echo "  --region $REGION"
echo ""

# Save CEV info for later use
cat > ../cev-info.txt <<EOF
ENGINE=$ENGINE
ENGINE_VERSION=$ENGINE_VERSION
AMI_ID=$AMI_ID
REGION=$REGION
EOF

echo "CEV info saved to: ../cev-info.txt"
