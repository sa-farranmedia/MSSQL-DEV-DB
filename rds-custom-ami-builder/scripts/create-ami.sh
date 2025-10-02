#!/bin/bash
# Create AMI from RDS Custom SQL Server builder instance

set -e

# Configuration
REGION=${AWS_REGION:-us-east-2}
PROJECT_NAME="legacy-wepabb"
ENV="dev"

# Get instance ID from Terraform output
cd ../terraform
INSTANCE_ID=$(terraform output -raw builder_instance_id)
cd ../scripts

echo "=========================================="
echo "Creating RDS Custom SQL Server AMI"
echo "=========================================="
echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"
echo ""

# Check instance state
echo "Checking instance state..."
INSTANCE_STATE=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --region $REGION \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text)

echo "Current state: $INSTANCE_STATE"

# Stop instance if it's running
if [ "$INSTANCE_STATE" != "stopped" ]; then
    echo "Stopping instance..."
    aws ec2 stop-instances --instance-ids $INSTANCE_ID --region $REGION

    echo "Waiting for instance to stop..."
    aws ec2 wait instance-stopped --instance-ids $INSTANCE_ID --region $REGION
    echo "Instance stopped."
fi

# Create AMI
AMI_NAME="rds-custom-sqlserver-2022-$(date +%Y%m%d-%H%M%S)"
echo ""
echo "Creating AMI: $AMI_NAME"

AMI_ID=$(aws ec2 create-image \
  --instance-id $INSTANCE_ID \
  --name "$AMI_NAME" \
  --description "RDS Custom SQL Server 2022 Enterprise - Built $(date +%Y-%m-%d)" \
  --region $REGION \
  --tag-specifications "ResourceType=image,Tags=[{Key=Name,Value=$AMI_NAME},{Key=Project,Value=$PROJECT_NAME},{Key=Environment,Value=$ENV},{Key=Purpose,Value=rds-custom}]" \
  --query 'ImageId' \
  --output text)

echo "AMI ID: $AMI_ID"
echo ""

# Wait for AMI to be available
echo "Waiting for AMI to become available (this takes 5-10 minutes)..."
aws ec2 wait image-available --image-ids $AMI_ID --region $REGION

echo ""
echo "=========================================="
echo "AMI Created Successfully!"
echo "=========================================="
echo "AMI ID: $AMI_ID"
echo "AMI Name: $AMI_NAME"
echo ""
echo "Next steps:"
echo "  1. Create Custom Engine Version (CEV):"
echo "     ./create-cev.sh $AMI_ID"
echo ""
echo "  2. Or manually create CEV:"
echo "     aws rds create-custom-db-engine-version \\"
echo "       --engine custom-sqlserver-ee \\"
echo "       --engine-version 15.00.4335.1.my-cev-v1 \\"
echo "       --database-installation-files-s3-bucket-name $PROJECT_NAME-cev-files \\"
echo "       --kms-key-id <your-kms-key> \\"
echo "       --image-id $AMI_ID \\"
echo "       --region $REGION"
echo ""

# Save AMI ID for later use
echo "$AMI_ID" > ../ami-id.txt
echo "AMI ID saved to: ../ami-id.txt"
