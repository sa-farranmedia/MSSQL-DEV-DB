<<<<<<< Updated upstream
# DEV Legacy WEBAPP Infrastructure - Operator Guide
=======
# Legacy WebApp - DEV Infrastructure

Complete Terraform infrastructure for DEV environment with Windows Server 2022 EC2 (SQL tooling only) and RDS Custom for SQL Server Developer Edition.
>>>>>>> Stashed changes

## Overview

This project provisions:

- **VPC**: Multi-AZ private/public subnets in `us-east-2`
- **Windows Server 2022 EC2**: SQL Server Management Studio (SSMS), .NET, Notepad++, NPS role
  - **IMPORTANT**: EC2 does NOT run SQL Server engine - only client tooling
- **RDS Custom for SQL Server**: Developer Edition with automated start/stop scheduler
- **SSM-only access**: No public IPs, IMDSv2 required
- **VPC Endpoints**: SSM, SSMMessages, EC2Messages, Logs, S3

## Prerequisites

### Required Tools

- Terraform >= 1.5.0
- AWS CLI >= 2.0
- Go >= 1.19 (for Terratest)
- Python >= 3.8 (for parser script)

### AWS Permissions

Your IAM user/role needs permissions for:
- VPC, EC2, RDS Custom (CEV, DB instances)
- IAM roles and policies
- EventBridge, Lambda, CloudWatch Logs
- S3 (for backend and media bucket)
- SSM Parameter Store
- Systems Manager (Session Manager)

### S3 Backend Bucket

Ensure the backend bucket exists with versioning enabled:

```bash
aws s3api head-bucket --bucket dev-sqlserver-supportfiles-backups-and-iso-files --region us-east-2
```

### SQL Server Media

Upload SQL Server 2022 Developer Edition media to S3:

```bash
# Upload ISO
aws s3 cp SQLServer2022-x64-ENU-Dev.iso \
  s3://dev-sqlserver-supportfiles-backups-and-iso-files/media/

# Upload Cumulative Update
aws s3 cp sqlserver2022-kb5041321-x64_1b40129fb51df67f28feb2a1ea139044c611b93f.exe \
  s3://dev-sqlserver-supportfiles-backups-and-iso-files/media/
```

## Quick Start

### 1. Extract Files

```bash
# Extract all files from artifact
python extract_artifact.py terraform_artifact.txt

# Set executable permissions on scripts
chmod +x rds-custom-ami-builder/scripts/*.sh
```

### 2. Build RDS Custom AMI (First Time Only)

See `rds-custom-ami-builder/README.md` for detailed instructions.

```bash
cd rds-custom-ami-builder/terraform

# Initialize and apply AMI builder
terraform init
terraform apply -var-file=ami-builder.tfvars

# Create AMI from instance (use scripts)
cd ../scripts
./create-ami.sh

# Create Custom Engine Version
./create-cev.sh

# After CEV is available, enable RDS Custom in main infrastructure
```

### 3. Deploy Main Infrastructure

```bash
cd terraform

# Initialize with backend configuration
terraform init -backend-config=envs/dev/backend.hcl

# Plan with dev variables
terraform plan -var-file=envs/dev/dev.tfvars

# Apply
terraform apply -var-file=envs/dev/dev.tfvars
```

### 4. Verify with Terratest

```bash
cd terratest

# Initialize Go modules
go mod download

# Run tests
go test -v -timeout 30m
```

## Configuration

### Main Variables (dev.tfvars)

Key variables to configure:

```hcl
project_name = "legacy-webapp"
env          = "dev"
region       = "us-east-2"

# VPC
vpc_cidr             = "10.42.0.0/16"
private_subnet_cidrs = ["10.42.0.0/20", "10.42.16.0/20", "10.42.32.0/20"]
public_subnet_cidrs  = ["10.42.240.0/24", "10.42.241.0/24"]

# EC2 IP Configuration (6 total IPs: 1 primary + 5 secondary)
additional_ip_strategy = "secondary_ips"
static_ips = [
  "10.42.0.60","10.42.0.61","10.42.0.62",
  "10.42.0.63","10.42.0.64","10.42.0.65"
]

# RDS Custom (enable after CEV created)
enable_rds_custom = false  # Set to true after CEV registration
enable_scheduler  = true

# SSM Access
ssm_allowed_iam_usernames = ["dev-brandon-leal"]
```

### Backend Configuration (backend.hcl)

```hcl
bucket = "dev-sqlserver-supportfiles-backups-and-iso-files"
key    = "tfstate/dev/infra.tfstate"
region = "us-east-2"
```

## Architecture

### Network Design

- **VPC CIDR**: `10.42.0.0/16`
- **Private Subnets** (3 AZs): `10.42.0.0/20`, `10.42.16.0/20`, `10.42.32.0/20`
- **Public Subnets** (2 AZs): `10.42.240.0/24`, `10.42.241.0/24`
- **NAT Gateway**: Single instance in first AZ (⚠️ **SPOF** - acceptable for DEV)
- **VPC Endpoints**: Interface endpoints for SSM services + S3 gateway endpoint

### IP Address Strategy

EC2 instance uses **secondary IPs only** (no multi-ENI):
- 1 primary IP (auto-assigned or first from list)
- 5 secondary IPs (assigned post-creation via AWS CLI)
- Total: **6 private IPs** on primary ENI

### Security

- **No Public IPs**: All access via SSM Session Manager
- **IMDSv2 Required**: Enforced on EC2 instance
- **EBS Encryption**: Enabled by default
- **VPC Endpoints**: Private communication with AWS services
- **Security Groups**: Principle of least privilege

### RDS Custom Scheduler

Automated start/stop for cost optimization:

| Schedule | Cron Expression | Time (UTC) | Time (MST) |
|----------|----------------|------------|------------|
| Start weekdays | `cron(0 13 ? * MON-FRI *)` | 1:00 PM | 6:00 AM |
| Stop weeknights | `cron(0 8 ? * TUE-FRI *)` | 8:00 AM | 1:00 AM |
| Stop weekend | `cron(0 0 ? * SAT *)` | 12:00 AM Sat | 5:00 PM Fri |

## Cost Considerations

### Estimated Monthly Costs (DEV)

- **EC2 m6i.2xlarge**: ~$250/month (24/7)
- **RDS Custom db.m5.xlarge**: ~$200/month (with scheduler: ~$100/month)
- **NAT Gateway**: ~$35/month
- **VPC Endpoints**: ~$30/month (4 interface endpoints)
- **Storage & Data Transfer**: ~$50/month

**Total**: ~$365-465/month depending on scheduler usage

### Single NAT Gateway (SPOF)

⚠️ **Known Limitation**: This configuration uses a single NAT Gateway for cost savings in DEV.

**Implications**:
- If the AZ hosting the NAT Gateway fails, private subnets lose internet access
- Acceptable for DEV; use Multi-AZ NAT for production

**To enable Multi-AZ NAT** (increases cost by ~$70/month):
- Create NAT Gateway in each public subnet
- Update route tables for each private subnet to use local AZ NAT

## Operations

### Connecting to Resources

See [DEVELOPER_README.md](DEVELOPER_README.md) for:
- SSM Session Manager setup
- RDP port forwarding to Windows EC2
- SQL Server port forwarding to RDS Custom
- SSMS connection strings

### Manual RDS Custom Controls

```bash
# Start RDS Custom instance
aws rds start-db-instance --db-instance-identifier dev-legacy-webapp-rds-custom

# Stop RDS Custom instance
aws rds stop-db-instance --db-instance-identifier dev-legacy-webapp-rds-custom

# Check status
aws rds describe-db-instances \
  --db-instance-identifier dev-legacy-webapp-rds-custom \
  --query 'DBInstances[0].DBInstanceStatus'
```

### Terraform State Management

Backend uses S3 with versioning:
- Versioning enables rollback if state corruption occurs
- Object Lock (Governance mode) provides WORM characteristics

**Optional**: Add DynamoDB table for state locking:

```hcl
# In backend.hcl
dynamodb_table = "terraform-state-lock"
```

## Troubleshooting

### EC2 Not Appearing in SSM

Check:
1. Instance has SSM IAM role attached
2. VPC endpoints for SSM are available
3. Security group allows HTTPS (443) from VPC CIDR
4. SSM agent is running: Check via EC2 console → Actions → Monitor

### Secondary IPs Not Assigned

Check `null_resource.assign_secondary_ips` logs:

```bash
terraform state show null_resource.assign_secondary_ips
```

Ensure:
- 15-30 second delay before assignment
- `--allow-reassignment` flag present
- IPs are from the correct subnet CIDR

### RDS Custom Won't Start

1. Check CEV status: `aws rds describe-db-engine-versions --engine custom-sqlserver-ee`
2. Verify S3 media bucket is accessible
3. Check CloudWatch logs for SQL Server service errors
4. Ensure NT AUTHORITY\SYSTEM has sysadmin role

### Scheduler Not Working

Check Lambda logs:

```bash
aws logs tail /aws/lambda/dev-legacy-webapp-rds-start --follow
aws logs tail /aws/lambda/dev-legacy-webapp-rds-stop --follow
```

Verify EventBridge rules are enabled:

```bash
aws events list-rules --name-prefix dev-legacy-webapp
```

### Terratest Failures

Common issues:
- **IMDSv2 not required**: Check `metadata_options` block in EC2 resource
- **Wrong IP count**: Verify `null_resource` successfully assigned 5 secondary IPs
- **Remote backend not detected**: Ensure `backend.tf` is present (not in .gitignore)

## Destroying Infrastructure

```bash
cd terraform

# Destroy all resources
terraform destroy -var-file=envs/dev/dev.tfvars

# Note: RDS Custom instances may require --auto-minor-version-upgrade=false flag
# If destroy fails, manually delete DB instance from console first
```

## Security Best Practices

1. **Secrets Management**: SA password stored in SSM Parameter Store (SecureString)
2. **Least Privilege**: IAM roles grant minimum required permissions
3. **Network Isolation**: Private subnets with no internet gateway routes
4. **Encryption**: EBS volumes encrypted, consider enabling RDS encryption
5. **Audit Logging**: Enable VPC Flow Logs and CloudTrail for compliance

## Important Notes

### EC2 = Tooling Only

⚠️ **The Windows EC2 instance does NOT run SQL Server engine**. It only contains:
- SQL Server Management Studio (SSMS)
- .NET Framework 3.5 and 4.8.1
- Notepad++
- Network Policy Server (NPS) role

All SQL Server databases run on **RDS Custom**, not EC2.

### Developer Edition License

This infrastructure uses SQL Server **Developer Edition**, which is:
- ✅ Free for dev/test
- ❌ Not licensed for production use

For production, switch to Enterprise or Standard Edition in the CEV.

## Support

For issues or questions:
1. Check CloudWatch Logs for service-specific errors
2. Review Terraform state: `terraform show`
3. Validate configuration: `terraform validate`
4. Consult AWS documentation for RDS Custom for SQL Server

## References

- [RDS Custom for SQL Server](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/custom-sqlserver.html)
- [Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terratest Documentation](https://terratest.gruntwork.io/)


