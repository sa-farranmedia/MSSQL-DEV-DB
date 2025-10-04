# RDS Custom AMI Builder

This directory contains Terraform configuration and scripts to build a custom AMI for RDS Custom for SQL Server Developer Edition.

## Overview

RDS Custom for SQL Server requires a BYOM (Bring Your Own Media) approach using Custom Engine Versions (CEV). This builder:

1. Launches a Windows Server 2019 EC2 instance
2. Installs SQL Server 2022 Developer Edition + Cumulative Update
3. Configures SQL Server according to RDS Custom requirements
4. Creates an AMI from the configured instance
5. Registers the AMI as a Custom Engine Version (CEV)
6. Enables deployment of RDS Custom instances using the CEV

## Prerequisites

### AWS Requirements

- AWS CLI configured with appropriate credentials
- IAM permissions for:
  - EC2 (launch instances, create AMIs)
  - RDS (create Custom Engine Versions)
  - S3 (read SQL Server media)
  - IAM (create roles for CEV)

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

### SA Password

Store the SA password in SSM Parameter Store:

```bash
aws ssm put-parameter \
  --name "/dev/legacy-webapp/rds/sa-password" \
  --value "YourStrongPassword123!" \
  --type "SecureString" \
  --region us-east-2
```

## Quick Start

### 1. Configure Variables

Edit `terraform/ami-builder.tfvars`:

```hcl
project_name = "legacy-webapp"
env          = "dev"
region       = "us-east-2"

s3_media_bucket = "dev-sqlserver-supportfiles-backups-and-iso-files"
sql_iso_key     = "media/SQLServer2022-x64-ENU-Dev.iso"
sql_cu_key      = "media/sqlserver2022-kb5041321-x64_1b40129fb51df67f28feb2a1ea139044c611b93f.exe"

# SA password from SSM Parameter Store
sa_password_ssm_path = "/dev/legacy-webapp/rds/sa-password"
```

### 2. Deploy Builder Instance

```bash
cd terraform

# Initialize Terraform
terraform init

# Plan
terraform plan -var-file=ami-builder.tfvars

# Apply (creates EC2 instance with SQL Server)
terraform apply -var-file=ami-builder.tfvars
```

**Wait time**: 30-45 minutes for SQL Server installation and configuration.

### 3. Create AMI

Once the instance is ready (check CloudWatch logs or SSM into instance):

```bash
cd ../scripts

# Create AMI from instance
./create-ami.sh

# Note the AMI ID from output
```

### 4. Register Custom Engine Version

```bash
# Register CEV with RDS
./create-cev.sh

# This creates CEV version like: 16.00.4210.1.dev-cev-20250103
```

### 5. Deploy RDS Custom

After CEV is registered and shows as "available":

```bash
# Update main infrastructure to enable RDS Custom
cd ../../terraform

# Edit envs/dev/dev.tfvars
# Set: enable_rds_custom = true

# Uncomment RDS instance in modules/rds_custom_dev/main.tf
# Update engine_version to match your CEV

# Deploy
terraform apply -var-file=envs/dev/dev.tfvars
```

Or use the deployment script:

```bash
cd rds-custom-ami-builder/scripts
./deploy-rds-custom.sh
```

### 6. Clean Up Builder Resources

```bash
cd ../terraform

# Destroy builder instance (keep AMI and CEV)
terraform destroy -var-file=ami-builder.tfvars
```

## File Structure

```
rds-custom-ami-builder/
├── README.md                    # This file
├── terraform/
│   ├── main.tf                  # Builder EC2 instance
│   ├── variables.tf             # Input variables
│   ├── ami-builder.tfvars       # Configuration values
│   └── install-sql-server.ps1   # SQL Server installation script
└── scripts/
    ├── create-ami.sh            # Create AMI from instance
    ├── create-cev.sh            # Register CEV with RDS
    └── deploy-rds-custom.sh     # Deploy RDS Custom instance
```

## SQL Server Configuration Requirements

The AMI builder follows RDS Custom for SQL Server BYOM requirements:

### Instance Configuration

- **Default Instance Name**: `MSSQLSERVER` (no named instances)
- **Service Accounts**:
  - Engine: `NT Service\MSSQLSERVER`
  - Agent: `NT Service\SQLSERVERAGENT`
- **Startup Type**: Manual for both Engine and Agent
- **SQL Browser**: Disabled (no UDP/1434)
- **TCP/IP**: Enabled on port 1433
- **Default Paths**: Use SQL Server defaults (don't override data/log paths)

### Security

- **SYSTEM Account**: Granted sysadmin role (required by RDS Custom)
- **SA Account**: SQL authentication enabled
- **Registry Configuration**: TCP/IP enabled via registry (not SMO/WMI)

### Sysprep

- Uses **EC2Launch v2** with `--shutdown` flag
- Ensures instance is properly generalized for AMI creation

## Installation Script Details

The `install-sql-server.ps1` script performs these steps:

1. Install AWS PowerShell modules (required for S3 access)
2. Download SQL Server media from S3
3. Mount ISO and locate setup.exe
4. Create ConfigurationFile.ini with proper settings
5. Install SQL Server silently (SA password via CLI, not INI)
6. Apply Cumulative Update
7. Configure TCP/IP via registry (port 1433)
8. Grant NT AUTHORITY\SYSTEM sysadmin role
9. Set services to Manual startup
10. Disable SQL Browser
11. Run EC2Launch v2 sysprep with shutdown

### PowerShell Variable Escaping

The script uses `$` to escape PowerShell variables in templatefile:

```powershell
# Terraform variables (single $)
$S3Bucket = "${s3_bucket}"
$SaPassword = "${sa_password}"

# PowerShell variables (double $)
${DriveLetter} = (Get-Volume).DriveLetter
${SetupPath} = "${DriveLetter}:\setup.exe"
```

## Scripts

### create-ami.sh

Creates an AMI from the builder instance:

```bash
#!/bin/bash
set -e

# Get instance ID from Terraform output
cd ../terraform
INSTANCE_ID=$(terraform output -raw builder_instance_id)
cd ../scripts

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

### create-cev.sh

Registers the AMI as a Custom Engine Version:

```bash
#!/bin/bash
set -e

# Prompt for AMI ID
read -p "Enter AMI ID: " AMI_ID

# Generate CEV version with date
CEV_DATE=$(date +%Y%m%d)
CEV_VERSION="16.00.4210.1.dev-cev-${CEV_DATE}"

echo "Creating Custom Engine Version: $CEV_VERSION"
echo "Using AMI: $AMI_ID"

# Create CEV
aws rds create-custom-db-engine-version \
  --engine custom-sqlserver-ee \
  --engine-version "$CEV_VERSION" \
  --database-installation-files-s3-bucket-name "dev-sqlserver-supportfiles-backups-and-iso-files" \
  --database-installation-files-s3-prefix "media/" \
  --image-id "$AMI_ID" \
  --region us-east-2

echo "✓ CEV creation initiated: $CEV_VERSION"
echo "Check status with:"
echo "aws rds describe-db-engine-versions --engine custom-sqlserver-ee --engine-version $CEV_VERSION"
```

### deploy-rds-custom.sh

Deploys RDS Custom instance using the CEV:

```bash
#!/bin/bash
set -e

cd ../../terraform

# Prompt for CEV version
read -p "Enter CEV version (e.g., 16.00.4210.1.dev-cev-20250103): " CEV_VERSION

echo "Updating RDS Custom configuration..."

# Update engine_version in RDS module
# (User must manually uncomment the resource and update version)

echo "Manual steps required:"
echo "1. Edit terraform/modules/rds_custom_dev/main.tf"
echo "2. Uncomment the aws_db_instance.rds_custom resource"
echo "3. Update engine_version to: $CEV_VERSION"
echo "4. Edit terraform/envs/dev/dev.tfvars"
echo "5. Set: enable_rds_custom = true"
echo ""
echo "Then run:"
echo "terraform apply -var-file=envs/dev/dev.tfvars"
```

## Verification

### Check Instance Status

```bash
# Get instance ID
cd terraform
terraform output builder_instance_id

# Start SSM session
aws ssm start-session --target <instance-id>

# In PowerShell session, check SQL Server
Get-Service MSSQLSERVER
Get-Service SQLSERVERAGENT

# Check logs
Get-Content C:\Windows\Temp\userdata.log -Tail 50
```

### Verify SQL Server Installation

```powershell
# Check SQL Server version
sqlcmd -S localhost -U sa -P "YourPassword" -Q "SELECT @@VERSION"

# Check TCP/IP is enabled on 1433
$TCP = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQLServer\SuperSocketNetLib\Tcp"
Get-ItemProperty -Path "$TCP\IPAll"

# Verify SYSTEM has sysadmin
sqlcmd -S localhost -U sa -P "YourPassword" -Q "SELECT name FROM sys.server_principals WHERE IS_SRVROLEMEMBER('sysadmin', name) = 1"
```

### Check CEV Status

```bash
# List all CEVs
aws rds describe-db-engine-versions \
  --engine custom-sqlserver-ee \
  --region us-east-2

# Check specific CEV
aws rds describe-db-engine-versions \
  --engine custom-sqlserver-ee \
  --engine-version "16.00.4210.1.dev-cev-20250103" \
  --region us-east-2
```

CEV must show status `available` before it can be used.

## Troubleshooting

### SQL Server Installation Fails

**Check logs**:
```powershell
# UserData log
Get-Content C:\Windows\Temp\userdata.log

# SQL Server setup log
Get-Content "C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\Log\Summary.txt"
```

**Common issues**:
- S3 media not accessible: Check IAM role permissions
- SA password not retrieved: Verify SSM Parameter Store path
- CU fails: Ensure base SQL version matches CU

### AMI Creation Fails

**Solutions**:
- Ensure instance is in "stopped" or "running" state
- Check EBS volumes are attached
- Verify instance is sysprepped (check for Sysprep log)

### CEV Registration Fails

**Common errors**:

1. **"AMI not found"**: Ensure AMI is in `available` state
2. **"Invalid engine version"**: Use format `16.00.4210.1.dev-cev-YYYYMMDD`
3. **"S3 bucket not accessible"**: Verify bucket name and RDS service role

**Required IAM for CEV**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::dev-sqlserver-supportfiles-backups-and-iso-files",
        "arn:aws:s3:::dev-sqlserver-supportfiles-backups-and-iso-files/*"
      ]
    }
  ]
}
```

### RDS Custom Instance Won't Start

**Solutions**:
1. Verify CEV status is `available`
2. Check CloudWatch Logs: `/aws/rds/instance/<instance-id>/`
3. Ensure custom IAM instance profile is attached
4. Verify SQL Server services are set to Manual (not Disabled)
5. Check NT AUTHORITY\SYSTEM has sysadmin role

## Best Practices

1. **Version CEV Names**: Use date-based versioning for easy tracking
2. **Test AMI**: Launch a test EC2 from AMI before creating CEV
3. **Document SA Password**: Keep secure but accessible for troubleshooting
4. **Backup AMIs**: Keep successful AMIs; don't delete immediately
5. **Tag Resources**: Use consistent tagging for cost tracking

## Cost Considerations

- **Builder Instance**: ~$0.20/hour (m5.xlarge)
- **AMI Storage**: ~$0.05/GB-month (150GB = ~$7.50/month)
- **CEV**: No additional cost (uses AMI)

**Recommendation**: Destroy builder instance immediately after AMI creation to save costs.

## Important Notes

### SQL Server Developer Edition

This configuration uses **SQL Server Developer Edition**, which is:
- ✅ Free for development and testing
- ❌ **NOT** licensed for production use

For production, you must:
1. Obtain proper SQL Server licenses (Enterprise or Standard)
2. Use licensed SQL Server media
3. Update CEV engine to match edition
4. Update RDS Custom instance configuration

### CEV Limitations

- **Region-specific**: CEV is created in specific region (us-east-2)
- **Version immutable**: Cannot modify CEV after creation
- **Deletion**: CEV can only be deleted if no DB instances use it

### RDS Custom vs RDS Managed

**RDS Custom gives you**:
- Full OS and SQL Server access
- Custom SQL Server configurations
- Ability to install 3rd party software

**You are responsible for**:
- OS patching
- SQL Server patching (CUs, service packs)
- Monitoring and maintenance
- Backup management (though automated backups available)

## Support

For issues:
1. Check CloudWatch Logs
2. Review SQL Server setup logs on EC2
3. Verify all prerequisites are met
4. Consult [AWS RDS Custom documentation](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/custom-sqlserver.html)


