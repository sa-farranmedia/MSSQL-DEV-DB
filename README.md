# DEV Legacy WEPABB Infrastructure - Operator Guide

## Overview

This Terraform project provisions a DEV-only environment in **us-east-2** for Windows Server 2022 EC2 instances with RDS Custom SQL Server scaffolding. The infrastructure includes:

- VPC (10.42.0.0/16) with 3 private and 2 public subnets across multiple AZs
- Windows Server 2022 EC2 instance (m6i.2xlarge) with .NET Framework, SSMS, Notepad++, and NPS
- VPC Endpoints for SSM access (no public IP required)
- RDS Custom SQL Server scaffolding with automated start/stop scheduling
- S3 backend with versioning and Object Lock governance mode

## Prerequisites

### AWS Account Setup

1. **S3 Backend Bucket**: Ensure bucket `dev-sqlserver-supportfiles-backups-and-iso-files` exists in `us-east-2`
   - Enable **S3 Versioning**
   - Enable **S3 Object Lock** (Governance mode) for state protection
   - Bucket policy should allow your IAM principal to read/write to `tfstate/dev/*`

2. **IAM Permissions**: Your IAM user/role needs:
   - `s3:GetObject`, `s3:PutObject`, `s3:ListBucket` on the state bucket
   - `dynamodb:*` for state locking (optional but recommended)
   - Full Terraform provisioning permissions:
     - EC2: VPC, subnets, security groups, instances, ENIs, VPC endpoints
     - IAM: roles, policies, instance profiles
     - SSM: parameters (for AMI lookup)
     - RDS: subnet groups, custom DB instances (when enabled)
     - Lambda: functions, permissions
     - EventBridge: rules, targets
     - CloudWatch: log groups
     - KMS: keys for encryption (if using custom KMS)

3. **Tools**:
   - Terraform >= 1.5.0
   - AWS CLI v2 configured with credentials
   - Go >= 1.21 (for Terratest)

### Backend Configuration

The S3 backend state file is stored at:
- Bucket: `dev-sqlserver-supportfiles-backups-and-iso-files`
- Key: `tfstate/dev/infra.tfstate`
- Region: `us-east-2`

**S3 Object Lock Note**: This is WORM/retention protection, NOT Terraform state locking. For state locking, consider adding a DynamoDB table (see `backend.tf` comments).

## Getting Started

### 1. Initialize Terraform

```bash
cd terraform
terraform init -backend-config=envs/dev/backend.hcl
```

This will:
- Configure the S3 backend
- Download required provider plugins
- Initialize modules

### 2. Review the Plan

```bash
terraform plan -var-file=envs/dev/dev.tfvars
```

Review all resources to be created. Pay attention to:
- VPC and subnet CIDRs
- EC2 instance type and ENI/IP strategy
- RDS Custom resources (commented by default)
- Scheduler rules (if enabled)

### 3. Apply the Configuration

```bash
terraform apply -var-file=envs/dev/dev.tfvars
```

Confirm with `yes` when prompted. Typical apply time: 10-15 minutes.

### 4. Verify Deployment

Check outputs:
```bash
terraform output
```

Verify EC2 is SSM-managed:
```bash
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$(terraform output -raw instance_id)" \
  --region us-east-2
```

### 5. Destroy Resources

When finished with DEV environment:
```bash
terraform destroy -var-file=envs/dev/dev.tfvars
```

**Warning**: This will delete all resources. Ensure you have backups of any data.

## Configuration Options

### ENI/IP Strategy

The `additional_ip_strategy` variable controls how 5 additional private IPs are allocated:

- **`secondary_ips`** (recommended): Assigns 5 secondary private IPs to the primary ENI
  - Simple, single ENI management
  - All IPs on one network interface

- **`multi_eni`**: Attaches additional ENIs and distributes IPs across them
  - More complex but allows ENI-level separation
  - Useful for specific routing/security scenarios

**Guardrails**: The configuration validates that m6i.2xlarge limits are not exceeded:
- Maximum 4 ENIs
- Maximum 15 IPv4 addresses per ENI

### Static IP Assignment

Set `static_ips` in `dev.tfvars`:
- `null`: Auto-assign from subnet CIDR (default)
- List of 5 IPs: Pin specific addresses (e.g., `["10.42.0.50", "10.42.0.51", ...]`)

### RDS Custom Scheduler

When `enable_scheduler = true`:
- **Start**: Weekdays at 1:00 PM UTC (6:00 AM MST)
- **Stop**: Weeknights at 8:00 AM UTC (1:00 AM MST)
- **Weekend Stop**: Saturday at midnight UTC

Lambda function uses Python 3.11 and requires RDS Custom instance to be provisioned.

## Cost Considerations

### Monthly Cost Estimates (us-east-2)

| Resource | Monthly Cost |
|----------|--------------|
| m6i.2xlarge EC2 (730 hrs) | ~$250 |
| NAT Gateway | ~$32 + data transfer |
| VPC Endpoints (4 interface) | ~$28 ($7 each) |
| RDS Custom (when enabled) | Variable (depends on instance type) |
| **Total (EC2 + networking)** | **~$310-350** |

**Cost Optimization**:
- NAT Gateway is single-AZ (SPOF acceptable for DEV)
- Scheduler reduces RDS runtime costs significantly
- Consider stopping EC2 when not in use (manual or scheduled)

### Single Points of Failure (DEV Acceptable)

- **NAT Gateway**: One NAT in one AZ. Outage affects outbound internet access.
  - Mitigation: VPC endpoints cover AWS service access (SSM, S3)
- **No multi-AZ failover**: This is a DEV environment, not HA.

## Running Terratest

Terratest validates the infrastructure deployment.

### Setup

```bash
cd terratest
go mod download
```

### Run Tests

Full test suite:
```bash
TEST_REGION=us-east-2 go test -v -timeout 30m
```

Short tests (skip heavy validations):
```bash
TEST_REGION=us-east-2 go test -v -short -timeout 10m
```

### What Tests Cover

- VPC creation with correct CIDR
- Subnet count and CIDR validation
- VPC Endpoints: SSM, SSMMessages, EC2Messages, CloudWatch Logs, S3 Gateway
- EC2 instance type (m6i.2xlarge)
- Secondary private IP count (5 IPs)
- SSM manageability (instance is managed)
- Terraform backend is remote S3

## Troubleshooting

### EC2 Not Showing as SSM Managed

1. Check instance profile attached: `aws ec2 describe-instances --instance-ids <id>`
2. Verify SSM agent running: Check CloudWatch Logs
3. Ensure VPC endpoints are available: `aws ec2 describe-vpc-endpoints`
4. Verify security group allows outbound HTTPS (443)

### Terraform State Lock Issues

If using DynamoDB locking and encountering lock errors:
```bash
# Force unlock (use carefully)
terraform force-unlock <LOCK_ID>
```

### UserData Script Failures

Check `C:\ProgramData\Amazon\EC2-Windows\Launch\Log\UserdataExecution.log` on the instance via SSM Session Manager.

### VPC Endpoint DNS Not Resolving

Ensure `enableDnsHostnames` and `enableDnsSupport` are true on the VPC (set automatically in this project).

## Security Best Practices

1. **No Public IPs**: EC2 instance has no public IP; access via SSM only
2. **IMDSv2 Required**: Metadata service requires session tokens
3. **Least Privilege IAM**: Instance profile has only necessary permissions
4. **Encrypted EBS**: All EBS volumes encrypted by default
5. **Security Groups**: No public ingress; RDS only accessible from VPC CIDR
6. **VPC Endpoints**: Private AWS API access without internet gateway traversal

## Maintenance

### Updating Windows

Connect via SSM Session Manager:
```bash
aws ssm start-session --target <instance-id> --region us-east-2
```

Then run Windows Update or:
```powershell
Install-Module PSWindowsUpdate -Force
Get-WindowsUpdate -Install -AcceptAll -AutoReboot
```

### Updating Terraform Modules

```bash
terraform get -update
terraform init -upgrade
```

### Rotating State Lock (DynamoDB)

If state becomes corrupted or locked:
1. Backup current state from S3
2. Force unlock if necessary
3. Verify lock table in DynamoDB
4. Re-run terraform init

## Support and References

- **Terraform AWS Provider**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- **RDS Custom for SQL Server**: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/custom-setup-sqlserver.html
- **Systems Manager Session Manager**: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html
- **Windows Server on AWS**: https://aws.amazon.com/windows/
