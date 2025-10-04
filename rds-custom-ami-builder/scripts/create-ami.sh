#!/bin/bash
set -e

INSTANCE_ID='i-095c3e90c505ae72d'

# Generate AMI name with timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
AMI_NAME="sqlserver2022-dev-cev-${TIMESTAMP}"

echo "Creating AMI from instance: $INSTANCE_ID"
echo "AMI Name: $AMI_NAME"

# Create AMI
AMI_ID=$(aws ec2 create-image \
  --instance-id "$INSTANCE_ID" \
  --name "$AMI_NAME" \
  --description "SQL Server 2022 Developer Edition with CU for RDS Custom CEV" \
  --no-reboot \
  --region us-east-2 \
  --query 'ImageId' \
  --output text)

echo "AMI creation initiated: $AMI_ID"
echo "Waiting for AMI to be available..."

aws ec2 wait image-available \
  --image-ids "$AMI_ID" \
  --region us-east-2

echo "✓ AMI is ready: $AMI_ID"
echo "Save this AMI ID for CEV registration"
```

