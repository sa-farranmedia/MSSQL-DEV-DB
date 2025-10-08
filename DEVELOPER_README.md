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
aws configure --profile dev-your-name

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
Server: localhost,1433
Authentication: SQL Server Authentication
Username: sqladmin
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

### Connection String Examples

**ADO.NET**:
```
Server=localhost,1433;Database=YourDB;User Id=sa;Password=<password>;TrustServerCertificate=True;
```

**JDBC**:
```
jdbc:sqlserver://localhost:1433;databaseName=YourDB;user=sa;password=<password>;trustServerCertificate=true;
```

**ODBC**:
```
Driver={ODBC Driver 17 for SQL Server};Server=localhost,1433;Database=YourDB;Uid=sa;Pwd=<password>;TrustServerCertificate=yes;
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

### Working Outside Scheduled Hours

**Note**: Starting RDS Custom can take 5-10 minutes.

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

### Can't Retrieve Parameter Store Values

**Error**: `AccessDeniedException`

**Solutions**:
1. Verify IAM permissions include `ssm:GetParameter`
2. Add `--region us-east-2` if using different default region
3. Check parameter name is exact (case-sensitive)
4. Ensure KMS key (if encrypted) grants decrypt permissions

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