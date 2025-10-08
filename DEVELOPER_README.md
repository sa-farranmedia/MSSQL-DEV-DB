# Developer Guide - Legacy WebApp DEV Environment

This guide covers how to connect to and use the DEV infrastructure for development work.

## Overview

The DEV environment consists of:
- **Windows EC2**: SQL Server client tooling (SSMS, .NET, etc.) - **NO SQL engine**
- **RDS Custom**: SQL Server Developer Edition database

All access is via **AWS Systems Manager Session Manager** (no RDP/SQL ports exposed publicly).

## Prerequisites

### Install AWS CLI

```bash
# macOS
brew install awscli

# Windows
# Download from: https://aws.amazon.com/cli/

# Verify installation
aws --version
```

### Install Session Manager Plugin

```bash
# macOS
brew install --cask session-manager-plugin

# Windows
# Download from: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html

# Verify installation
session-manager-plugin
```

### Configure AWS CLI

```bash
# Configure default profile
aws configure

# Or use named profile
aws configure --profile dev-brandon-leal

# Verify access
aws sts get-caller-identity
```

## Connecting to Windows EC2

### Method 1: Direct SSM Session (Console/PowerShell)

Start a PowerShell session directly:

```bash
# Get instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=dev-legacy-webapp-ec2" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

# Start session
aws ssm start-session --target $INSTANCE_ID
```

This opens a PowerShell prompt on the Windows server.

### Method 2: RDP via Port Forwarding

For GUI access with RDP:

```bash
# Get instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=dev-legacy-webapp-ec2" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

# Start port forward (RDP on local port 13389)
aws ssm start-session \
  --target $INSTANCE_ID \
  --document-name AWS-StartPortForwardingSession \
  --parameters "portNumber=3389,localPortNumber=13389"
```

**Keep this terminal open**. In another window, connect with RDP client:

```
Server: localhost:13389
Username: Administrator
Password: [Get from SSM Parameter Store - see below]
```

#### Get Administrator Password

```bash
# Retrieve password from Parameter Store
aws ssm get-parameter \
  --name /dev/legacy-webapp/ec2/admin-password \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text
```

Or retrieve the Windows password using EC2 key pair:

```bash
aws ec2 get-password-data \
  --instance-id $INSTANCE_ID \
  --priv-launch-key /path/to/keypair.pem
```

### RDP Clients

**macOS**: Microsoft Remote Desktop (App Store)
**Windows**: Built-in Remote Desktop Connection (`mstsc.exe`)
**Linux**: Remmina, rdesktop, or xfreerdp

## Connecting to SQL Server (RDS Custom)

### Method 1: Port Forward + SSMS (from local machine)

Forward SQL port to your local machine:

```bash
# Get RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier dev-legacy-webapp-rds-custom \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

# Get EC2 instance ID (as jump host)
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=dev-legacy-webapp-ec2" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

# Start port forward (SQL Server on local port 11433)
aws ssm start-session \
  --target $INSTANCE_ID \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$RDS_ENDPOINT\"],\"portNumber\":[\"1433\"],\"localPortNumber\":[\"1433\"]}"
```

**Keep this terminal open**. Connect with SSMS or any SQL client:

```
Server: localhost,11433
Authentication: SQL Server Authentication
Username: sa
Password: [Get from Parameter Store - see below]
```

#### Get SA Password

```bash
# Retrieve SA password from Parameter Store
aws ssm get-parameter \
  --name /dev/legacy-webapp/rds/sa-password \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text
```

### Method 2: SSMS from Windows EC2

1. RDP to Windows EC2 (see above)
2. Open SQL Server Management Studio (SSMS)
3. Connect to RDS Custom:

```
Server: <rds-custom-endpoint>
Authentication: SQL Server Authentication
Username: sa
Password: [From Parameter Store]
```

Get RDS endpoint from EC2 PowerShell:

```powershell
# Get RDS endpoint
aws rds describe-db-instances `
  --db-instance-identifier dev-legacy-webapp-rds-custom `
  --query 'DBInstances[0].Endpoint.Address' `
  --output text
```

Or find in Terraform outputs:

```bash
terraform output rds_custom_endpoint
```

### Connection String Examples

**ADO.NET**:
```
Server=localhost,11433;Database=YourDB;User Id=sa;Password=<password>;TrustServerCertificate=True;
```

**JDBC**:
```
jdbc:sqlserver://localhost:11433;databaseName=YourDB;user=sa;password=<password>;trustServerCertificate=true;
```

**ODBC**:
```
Driver={ODBC Driver 17 for SQL Server};Server=localhost,11433;Database=YourDB;Uid=sa;Pwd=<password>;TrustServerCertificate=yes;
```

## Retrieving Credentials

All sensitive credentials are stored in **AWS Systems Manager Parameter Store**.

### List All Parameters

```bash
aws ssm get-parameters-by-path \
  --path /dev/legacy-webapp/ \
  --recursive \
  --query 'Parameters[*].[Name]' \
  --output table
```

### Get Specific Parameter

```bash
# EC2 Administrator password
aws ssm get-parameter \
  --name /dev/legacy-webapp/ec2/admin-password \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text

# RDS SA password
aws ssm get-parameter \
  --name /dev/legacy-webapp/rds/sa-password \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text
```

## Common Development Tasks

### Deploy Application to EC2

1. RDP to EC2 or use SSM session
2. Application files can be:
   - Downloaded from S3
   - Uploaded via RDP clipboard share
   - Pulled from Git repository

Example using S3:

```powershell
# From EC2 PowerShell
Read-S3Object `
  -BucketName dev-sqlserver-supportfiles-backups-and-iso-files `
  -Key "applications/my-app.zip" `
  -File "C:\Temp\my-app.zip"

# Extract
Expand-Archive -Path "C:\Temp\my-app.zip" -DestinationPath "C:\Apps\my-app"
```

### Restore Database Backup

```powershell
# Download backup from S3
Read-S3Object `
  -BucketName dev-sqlserver-supportfiles-backups-and-iso-files `
  -Key "backups/MyDatabase.bak" `
  -File "D:\Backups\MyDatabase.bak"

# Restore via SSMS or T-SQL
RESTORE DATABASE [MyDatabase]
FROM DISK = N'D:\Backups\MyDatabase.bak'
WITH FILE = 1,
MOVE N'MyDatabase' TO N'D:\MSSQL\DATA\MyDatabase.mdf',
MOVE N'MyDatabase_log' TO N'D:\MSSQL\DATA\MyDatabase_log.ldf',
NOUNLOAD, STATS = 5
GO
```

### Check RDS Custom Status

```bash
# Check if RDS is running
aws rds describe-db-instances \
  --db-instance-identifier dev-legacy-webapp-rds-custom \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text

# Check scheduler status
aws events list-rules --name-prefix dev-legacy-webapp
```

### Manually Start/Stop RDS Custom

```bash
# Start (if stopped by scheduler)
aws rds start-db-instance \
  --db-instance-identifier dev-legacy-webapp-rds-custom

# Stop (for extended breaks)
aws rds stop-db-instance \
  --db-instance-identifier dev-legacy-webapp-rds-custom
```

**Note**: Starting RDS Custom can take 5-10 minutes.

## Development Workflow

### Typical Daily Workflow

1. **Morning** (6 AM MST / 1 PM UTC):
   - RDS Custom auto-starts via scheduler
   - Wait 5-10 minutes for SQL Server to be ready

2. **Connect**:
   - Start port forward: `aws ssm start-session ...`
   - Connect SSMS to `localhost,11433`
   - Or RDP to EC2 if GUI work needed

3. **Develop**:
   - Write/test application code
   - Run database migrations
   - Test queries in SSMS

4. **Evening** (1 AM MST / 8 AM UTC):
   - RDS Custom auto-stops via scheduler
   - Ensure all work is committed/backed up

### Working Outside Scheduled Hours

If you need RDS Custom outside scheduled hours:

```bash
# Start manually
aws rds start-db-instance \
  --db-instance-identifier dev-legacy-webapp-rds-custom

# Work...

# Stop when done (to save costs)
aws rds stop-db-instance \
  --db-instance-identifier dev-legacy-webapp-rds-custom
```

## Scheduler Times

| Event | Cron | UTC Time | MST Time | Notes |
|-------|------|----------|----------|-------|
| Start weekday | `cron(0 13 ? * MON-FRI *)` | 1:00 PM | 6:00 AM | Monday-Friday |
| Stop weeknight | `cron(0 8 ? * TUE-FRI *)` | 8:00 AM | 1:00 AM | Tuesday-Friday |
| Stop weekend | `cron(0 0 ? * SAT *)` | 12:00 AM Sat | 5:00 PM Fri | Friday night |

**Grace Period**: Allow 5-10 minutes after scheduled start time for SQL Server to be fully ready.

## Troubleshooting

### Can't Start SSM Session

**Error**: `TargetNotConnected`

**Solutions**:
1. Verify EC2 is running: `aws ec2 describe-instances --instance-ids $INSTANCE_ID`
2. Check SSM agent status in EC2 console
3. Verify VPC endpoints exist and security groups allow HTTPS
4. Ensure your IAM user has `ssm:StartSession` permission

### Port Forward Disconnects

**Solutions**:
1. Check timeout settings in SSM preferences
2. Ensure local firewall allows loopback connections
3. Try increasing `localPortNumber` (avoid reserved ports)
4. Verify Session Manager plugin is up to date

### SSMS Can't Connect to localhost,11433

**Solutions**:
1. Verify port forward is active (check terminal window)
2. Ensure RDS Custom is started: `aws rds describe-db-instances`
3. Check credentials from Parameter Store
4. Try using `127.0.0.1,11433` instead of `localhost,11433`
5. Verify SQL Server service is running (may take 5-10 min after RDS start)

### RDS Custom Won't Start

**Solutions**:
1. Check scheduler disabled it: Review EventBridge rules
2. Verify CEV status: `aws rds describe-db-engine-versions --engine custom-sqlserver-dev`
3. Check CloudWatch logs for errors: `/aws/rds/instance/dev-legacy-webapp-rds-custom/`
4. Ensure IAM roles have correct permissions
5. Contact AWS support if instance shows `incompatible-parameters`

### Can't Retrieve Parameter Store Values

**Error**: `AccessDeniedException`

**Solutions**:
1. Verify IAM permissions include `ssm:GetParameter`
2. Add `--region us-east-2` if using different default region
3. Check parameter name is exact (case-sensitive)
4. Ensure KMS key (if encrypted) grants decrypt permissions

## Best Practices

### Security

1. **Never hardcode credentials** - always use Parameter Store
2. **Use named AWS profiles** for different environments
3. **Close port forwards** when not in use
4. **Lock Windows EC2** when stepping away (RDP session)
5. **Rotate passwords** periodically (update Parameter Store)

### Cost Optimization

1. **Stop RDS Custom** when not needed (outside work hours)
2. **Use scheduler** - don't override unless necessary
3. **Monitor costs** via AWS Cost Explorer
4. **Clean up test databases** to reduce storage costs

### Performance

1. **Test queries** in SSMS before deploying to production
2. **Monitor RDS CloudWatch metrics** for resource usage
3. **Index tuning** - use Database Engine Tuning Advisor on EC2
4. **Backup strategy** - use RDS Custom automated backups

## Quick Reference

### Essential Commands

```bash
# Get EC2 instance ID
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=dev-legacy-webapp-ec2" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text

# Get RDS endpoint
aws rds describe-db-instances \
  --db-instance-identifier dev-legacy-webapp-rds-custom \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text

# RDP port forward
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters "portNumber=3389,localPortNumber=13389"

# SQL port forward
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<rds-endpoint>"],"portNumber":["1433"],"localPortNumber":["11433"]}'

# Get SA password
aws ssm get-parameter \
  --name /dev/legacy-webapp/rds/sa-password \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text
```

## Support

For infrastructure issues:
- Check CloudWatch Logs
- Review Terraform state
- Consult main [README.md](README.md)

For application issues:
- Contact development team
- Check application logs on EC2 (Event Viewer, IIS logs, etc.)


