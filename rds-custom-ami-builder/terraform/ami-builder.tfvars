project_name = "legacy-webapp"
env          = "dev"
region       = "us-east-2"

# ami-05f848027a4b5cd25
base_ami_ssm_param = "/aws/service/ami-windows-latest/Windows_Server-2019-English-Full-Base"
filter  = "Windows_Server-2019-English-Full-Base-*"

# being built public does not stop you from becoming an RDS custom instance on a private VPC
builder_public       = true
create_ssm_endpoints = false
# Generate your own then pass it in
# REGION=us-east-2
# KEY_NAME=brand-east2
# aws ec2 create-key-pair --region "$REGION" --key-name "$KEY_NAME" \
#   --query 'KeyMaterial' --output text > ~/.ssh/${KEY_NAME}.pem
# chmod 600 ~/.ssh/${KEY_NAME}.pem

key_name = "brand-east2"  # or whatever you created