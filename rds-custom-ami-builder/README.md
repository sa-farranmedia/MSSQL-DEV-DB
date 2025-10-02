# RDS Custom SQL Server AMI Builder

Complete automation for building RDS Custom for SQL Server AMIs, creating Custom Engine Versions (CEVs), and deploying RDS Custom instances.

## Overview

RDS Custom for SQL Server requires a specially prepared Windows AMI that meets AWS requirements. This toolkit automates:

1. **AMI Builder Instance**: Terraform provisions a temporary EC2 instance
2. **SQL Server Installation**: Automated PowerShell script installs SQL Server from S3 media
3. **RDS Custom Configuration**: Applies all required registry settings, services, and permissions
4. **AMI Creation**: Script or manual process to create AMI from configured instance
5. **CEV Creation**: Terraform or CLI creates Custom Engine Version
6. **RDS Instance**: Deploy RDS Custom SQL Server instance

## Prerequisites

- **S3 Media Bucket**: SQL Server ISO and Cumulative Update files uploaded
- **AWS Permissions**: EC2, RDS, IAM, S3, Systems Manager
- **Terraform**: >= 1.5.0
- **AWS CLI**: v2 configured
- **PowerShell**: For local automation scripts (optional)

## Quick Start

```bash
# 1. Build the AMI
cd rds-custom-ami-builder/terraform
terraform init
terraform apply -var-file=ami-builder.tfvars

# 2. Wait for installation to complete (check SSM Run Command or CloudWatch Logs)
# Installation takes 30-45 minutes

# 3. Create the AMI
./scripts/create-ami.sh

# 4. Create the CEV
./scripts/create-cev.sh

# 5. Deploy RDS Custom instance (back in main terraform)
cd ../../terraform
terraform apply -var="enable_rds_custom=true" -var-file=envs/dev/dev.tfvars
```

## Detailed Process

### Step 1: Prepare SQL Server Media in S3

Upload your SQL Server installation files:

```bash
aws s3 cp SERVER_EVAL_x64FRE_en-us.iso \
  s3://dev-sqlserver-supportfiles-backups-and-iso-files/media/

aws s3 cp sqlserver2022-kb5041321-x64_*.exe \
  s3://dev-sqlserver-supportfiles-backups-and-iso-files/media/
```

### Step 2: Deploy AMI Builder Instance

```bash
cd rds-custom-ami-builder/terraform
terraform init
terraform apply -var-file=ami-builder.tfvars
```

This creates:
- Windows Server 2019/2022 EC2 instance (RDS Custom compatible)
- Mounts SQL Server ISO from S3
- Installs SQL Server Enterprise with required features
- Applies cumulative update
- Configures RDS Custom prerequisites
- Runs sysprep preparation

### Step 3: Monitor Installation Progress

```bash
# Check SSM Run Command status
aws ssm list-command-invocations \
  --instance-id $(terraform output -raw builder_instance_id) \
  --region us-east-2

# Or check CloudWatch Logs
aws logs tail /aws/rds-custom/ami-builder --follow --region us-east-2
```

### Step 4: Create AMI

Once installation completes (instance will stop automatically):

```bash
# Using provided script
./scripts/create-ami.sh

# Or manually
export INSTANCE_ID=$(terraform output -raw builder_instance_id)
aws ec2 create-image \
  --instance-id $INSTANCE_ID \
  --name "rds-custom-sqlserver-2022-$(date +%Y%m%d-%H%M%S)" \
  --description "RDS Custom SQL Server 2022 Enterprise with CU" \
  --region us-east-2 \
  --tag-specifications 'ResourceType=image,Tags=[{Key=Name,Value=rds-custom-sqlserver-2022}]'
```

Wait for AMI to become available (5-10 minutes):

```bash
aws ec2 describe-images --image-ids ami-xxxxx --region us-east-2
```

### Step 5: Create Custom Engine Version (CEV)

```bash
# Edit scripts/create-cev.sh with your AMI ID
export AMI_ID="ami-xxxxxxxxxxxxx"

# Run CEV creation
./scripts/create-cev.sh

# Or use Terraform (update main terraform with AMI ID)
cd ../../terraform
terraform apply -var="rds_custom_ami_id=ami-xxxxx" -var-file=envs/dev/dev.tfvars
```

### Step 6: Deploy RDS Custom Instance

Uncomment the RDS Custom resources in `terraform/modules/rds_custom_dev/main.tf` and apply:

```bash
cd ../../terraform
terraform apply -var="enable_rds_custom=true" -var-file=envs/dev/dev.tfvars
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ 1. AMI Builder Process                                       │
│                                                               │
│  S3 Media Bucket                                             │
│  └── SQL Server ISO + CU                                     │
│       │                                                       │
│       ↓                                                       │
│  EC2 AMI Builder Instance                                    │
│  ├── Mount ISO via PowerShell                                │
│  ├── Install SQL Server Enterprise                           │
│  │   └── Features: Engine, Replication, Full-Text           │
│  ├── Apply Cumulative Update                                 │
│  ├── Configure RDS Custom Prerequisites                      │
│  │   ├── Registry settings                                   │
│  │   ├── Windows services                                    │
│  │   └── Permissions & security                              │
│  └── Run EC2Launch/Sysprep                                   │
│       │                                                       │
│       ↓                                                       │
│  Create AMI Snapshot                                         │
└───────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ 2. CEV & RDS Custom Deployment                               │
│                                                               │
│  Custom AMI                                                   │
│       │                                                       │
│       ↓                                                       │
│  Create Custom Engine Version (CEV)                          │
│  └── Register AMI with RDS Custom                            │
│       │                                                       │
│       ↓                                                       │
│  Deploy RDS Custom DB Instance                               │
│  ├── Uses CEV                                                │
│  ├── Managed by RDS (backups, patching, monitoring)          │
│  └── Full OS & SQL Server access via SSM                     │
└───────────────────────────────────────────────────────────────┘
```

## Configuration Files

### ami-builder.tfvars

```hcl
project_name = "legacy-wepabb"
env          = "dev"
region       = "us-east-2"

# Use existing VPC from main project
vpc_id               = "vpc-xxxxx"
subnet_id            = "subnet-xxxxx"

# SQL Server media in S3
s3_media_bucket = "dev-sqlserver-supportfiles-backups-and-iso-files"
sql_iso_key     = "media/SERVER_EVAL_x64FRE_en-us.iso"
sql_cu_key      = "media/sqlserver2022-kb5041321-x64_1b40129fb51df67f28feb2a1ea139044c611b93f.exe"

# SQL Server configuration
sql_version         = "2022"
sql_edition         = "Enterprise"
sql_instance_name   = "MSSQLSERVER"
sql_collation       = "SQL_Latin1_General_CP1_CI_AS"

# Instance configuration
builder_instance_type = "m5.xlarge"
builder_volume_size   = 150  # GB - needs space for SQL Server
```

## SQL Server Features Installed

The AMI builder installs these SQL Server features (required by RDS Custom):

- **Database Engine Services** (`SQLENGINE`)
- **SQL Server Replication** (`REPLICATION`)
- **Full-Text Search** (`FULLTEXT`)
- **Client Tools Connectivity** (`CONN`)
- **Management Tools - Basic** (`SSMS`, `ADV_SSMS`)

## RDS Custom Prerequisites Applied

The installation script configures:

### Registry Settings
- SQL Server service accounts
- TCP/IP enabled on port 1433
- Mixed mode authentication
- Error log configuration

### Windows Services
- SQL Server service (automatic start)
- SQL Server Agent (automatic start)
- SQL Server Browser (disabled for RDS Custom)

### Security & Permissions
- SA password set (stored in SSM Parameter Store)
- RDS Custom IAM role permissions
- Windows Firewall rules
- Audit logging enabled

### EC2Launch/Sysprep
- Generalized image for AMI creation
- Admin password randomization
- Computer name randomization

## Troubleshooting

### Installation Failed

Check logs:
```bash
# SSM command output
aws ssm get-command-invocation \
  --instance-id $INSTANCE_ID \
  --command-id $COMMAND_ID \
  --region us-east-2

# CloudWatch Logs
aws logs tail /aws/rds-custom/ami-builder --follow
```

Common issues:
- **ISO not found**: Verify S3 paths in variables
- **Insufficient disk space**: Increase `builder_volume_size`
- **Installation timeout**: SQL Server install can take 30+ minutes

### AMI Creation Failed

Ensure instance is fully stopped before creating AMI:
```bash
aws ec2 describe-instances --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].State.Name'
```

### CEV Creation Failed

Validate AMI meets RDS Custom requirements:
```bash
# Check AMI is available
aws ec2 describe-images --image-ids $AMI_ID

# Validate AMI tags
aws ec2 describe-images --image-ids $AMI_ID \
  --query 'Images[0].Tags'
```

### RDS Instance Won't Start

Check RDS Custom logs:
```bash
aws rds describe-db-instances \
  --db-instance-identifier dev-legacy-wepabb-sqlserver

aws logs tail /aws/rds/custom/dev-legacy-wepabb-sqlserver/agent \
  --follow --region us-east-2
```

## Cost Optimization

### Builder Instance
- **Run only when building**: Destroy after AMI creation
- **Right-size**: Use m5.xlarge (sufficient for installation)
- **Spot instances**: Consider for non-critical builds

### AMI Storage
- **EBS snapshots**: ~$0.05/GB/month
- **Cleanup old AMIs**: Deregister and delete snapshots when not needed

### RDS Custom Instance
- **Scheduler**: Use EventBridge rules to stop when not in use
- **Right-size**: Start with db.m5.xlarge and adjust based on workload

## Security Best Practices

1. **SA Password**: Stored in SSM Parameter Store (SecureString)
2. **Encryption**: EBS volumes encrypted by default
3. **IAM Roles**: Least-privilege for builder and RDS Custom
4. **Security Groups**: No public access, VPC-only
5. **Audit Logs**: CloudWatch Logs enabled for all SQL Server logs
6. **Sysprep**: Ensures no sensitive data in AMI

## References

- [RDS Custom for SQL Server Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/custom-setup-sqlserver.html)
- [CEV Creation Guide](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/custom-cev.html)
- [SQL Server Installation Guide](https://learn.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server)
