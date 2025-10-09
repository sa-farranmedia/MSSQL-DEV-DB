project_name = "legacy-webapp"
env          = "dev"
region       = "us-east-2"

# FIXED: Use AWS-provided SQL Server 2022 Developer on Windows Server 2019
# This AMI is already RDS Custom compatible!
base_ami_ssm_param = "/aws/service/ami-windows-latest/Windows_Server-2019-English-Full-Base"

# being built public does not stop you from becoming an RDS custom instance on a private VPC
builder_public       = true
create_ssm_endpoints = true

# Keygen
# REGION=us-east-2
# KEY_NAME=legacy_ec2
# aws ec2 create-key-pair --region "$REGION" --key-name "$KEY_NAME" \
#   --query 'KeyMaterial' --output text > ~/.ssh/${KEY_NAME}.pem
# chmod 600 ~/.ssh/${KEY_NAME}.pem
key_name = "brand-east2"