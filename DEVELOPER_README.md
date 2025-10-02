# DEV Legacy WEBAPP Infrastructure - Developer Guide

## Overview

This guide helps developers connect to the Windows Server 2022 EC2 instance and RDS Custom SQL Server using AWS Systems Manager (SSM) port forwarding. No public IPs or bastion hosts are required.

## Prerequisites

Before connecting, ensure you have:

1. **AWS CLI v2** installed and configured
   ```bash
   aws --version  # Should be 2.x
   ```

2. **AWS Session Manager Plugin** installed
   - Download: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
   - Verify: `session-manager-plugin`

3. **IAM Permissions**: Your AWS user/role needs:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "ssm:StartSession",
           "ssm:DescribeInstanceInformation",
           "ssm:TerminateSession"
         ],
         "Resource": [
           "arn:aws:ec2:us-east-2:*:instance/*",
           "arn:aws:ssm:us-east-2:*:document/AWS-StartPortForwardingSession"
         ],
         "Condition": {
           "StringLike": {
             "ssm:resourceTag/project": "legacy-wepabb"
           }
         }
       }
     ]
   }
   ```

4. **SQL Server Management Studio (SSMS)** installed locally (for database access)
   - Download: https://aka.ms/ssmsfullsetup

5. **Get Instance ID**: Retrieve from Terraform outputs
   ```bash
   cd terraform
   export INSTANCE_ID=$(terraform output -raw instance_id)
   echo $INSTANCE_ID
   ```

## Connecting to the EC2 Instance

### Method 1: Interactive Shell (PowerShell Session)

Start an interactive PowerShell session on the EC2 instance:

```bash
aws ssm start-session \
  --target $INSTANCE_ID \
  --region us-east-2
```

Once connected, you can run PowerShell commands directly:
```powershell
# Check Windows version
Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion

# Verify .NET installations
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP' -Recurse

# Check installed software
Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object DisplayName, DisplayVersion

# Check NPS service
Get-Service IAS
```

Exit session: Type `exit`

### Method 2: Port Forwarding (RDP Access)

Forward local port to RDP (3389) on the instance:

```bash
aws ssm start-session \
  --target $INSTANCE_ID \
  --region us-east-2 \
  --document-name AWS-StartPortForwardingSession \
  --parameters "portNumber=3389,localPortNumber=13389"
```

Keep this terminal open. In another terminal, connect RDP:
```bash
# Windows
mstsc /v:localhost:13389

# Mac (Microsoft Remote Desktop)
# Open Microsoft Remote Desktop app
# Add PC: localhost:13389
# Username: Administrator (get password from AWS console or SSM Parameter)

# Linux
rdesktop localhost:13389
```

**Get Windows Password**:
```bash
# If you have the EC2 key pair
aws ec2 get-password-data \
  --instance-id $INSTANCE_ID \
  --region us-east-2 \
  --priv-launch-key /path/to/private-key.pem
```

## Connecting to RDS Custom SQL Server

### Step 1: Get RDS Endpoint

Retrieve the RDS Custom endpoint from Terraform outputs (when RDS is provisioned):

```bash
cd terraform
export RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
export RDS_PORT=1433
echo "RDS Endpoint: $RDS_ENDPOINT"
```

### Step 2: Start Port Forwarding to RDS

Forward local port to RDS SQL Server port (1433):

```bash
aws ssm start-session \
  --target $INSTANCE_ID \
  --region us-east-2 \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"portNumber\":[\"1433\"],\"localPortNumber\":[\"11433\"],\"host\":[\"$RDS_ENDPOINT\"]}"
```

**Important**: Keep this terminal window open while connected.

### Step 3: Connect SSMS to RDS via Port Forward

1. Open **SQL Server Management Studio** on your local machine

2. In the "Connect to Server" dialog:
   - **Server type**: Database Engine
   - **Server name**: `localhost,11433` (note the comma, not colon)
   - **Authentication**: SQL Server Authentication
   - **Login**: `admin` (or your configured RDS master username)
   - **Password**: Your RDS master password

3. Click **Connect**

You're now connected to RDS Custom SQL Server through the EC2 instance!

### Alternative: Direct Connection (if VPN or VPC peering exists)

If you have network connectivity to the VPC (e.g., VPN, Direct Connect):

```
Server name: <RDS_ENDPOINT>,1433
Authentication: SQL Server Authentication
Login: admin
Password: <your-password>
```

## Common Connection Scenarios

### Scenario 1: Quick Database Query via EC2

1. Start SSM session to EC2
   ```bash
   aws ssm start-session --target $INSTANCE_ID --region us-east-2
   ```

2. From PowerShell on EC2, run SQL query:
   ```powershell
   # Using SQLCMD (pre-installed)
   sqlcmd -S $env:RDS_ENDPOINT -U admin -P 'YourPassword' -Q "SELECT @@VERSION"
   ```

### Scenario 2: File Transfer to EC2

Upload a file using SSM Session Manager:

```bash
# Create a temporary S3 location
aws s3 cp myfile.sql s3://dev-sqlserver-supportfiles-backups-and-iso-files/temp/

# In SSM session on EC2:
Read-S3Object -BucketName dev-sqlserver-supportfiles-backups-and-iso-files -Key temp/myfile.sql -File C:\temp\myfile.sql
```

### Scenario 3: Debugging Network Connectivity

From SSM session on EC2, test RDS connectivity:

```powershell
# Test port 1433 connectivity
Test-NetConnection -ComputerName $env:RDS_ENDPOINT -Port 1433

# Check security group rules
# (Ensure EC2 security group can reach RDS security group on port 1433)

# DNS resolution
Resolve-DnsName $env:RDS_ENDPOINT
```

## Port Forwarding Reference

### AWS SSM Port Forwarding Documents

1. **AWS-StartPortForwardingSession**: Forward to a port on the instance itself
   - Use for: RDP (3389), custom application ports
   - Example: RDP access to EC2

2. **AWS-StartPortForwardingSessionToRemoteHost**: Forward to a remote host via the instance
   - Use for: RDS, other VPC resources not directly SSM-accessible
   - Example: SQL Server on RDS Custom

### Common Ports

| Service | Port | Local Forward |
|---------|------|---------------|
| RDP (EC2) | 3389 | `localPortNumber=13389` |
| SQL Server (RDS) | 1433 | `localPortNumber=11433` |
| HTTP (custom app) | 80 | `localPortNumber=8080` |
| HTTPS (custom app) | 443 | `localPortNumber=8443` |

## Troubleshooting

### SSM Session Won't Start

**Error**: "Target is not connected"

**Causes**:
- SSM Agent not running on EC2
- VPC endpoints for SSM not configured
- Instance profile missing SSM permissions
- Security group blocking outbound HTTPS (443)

**Fix**:
1. Check instance status:
   ```bash
   aws ssm describe-instance-information --region us-east-2
   ```
2. Verify VPC endpoints exist:
   ```bash
   aws ec2 describe-vpc-endpoints --region us-east-2 --filters "Name=service-name,Values=com.amazonaws.us-east-2.ssm"
   ```
3. Check CloudWatch Logs for SSM agent errors

### Port Forward Connection Refused

**Error**: "Connection refused" on `localhost:11433`

**Causes**:
- RDS instance stopped or not running
- Security group blocking port 1433 from EC2
- RDS endpoint incorrect
- Port forward session terminated

**Fix**:
1. Verify RDS running:
   ```bash
   aws rds describe-db-instances --region us-east-2 --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]'
   ```
2. Check RDS security group inbound rule allows TCP/1433 from VPC CIDR or EC2 security group
3. Ensure port forward session is active (keep terminal open)

### SSMS Connection Timeout

**Error**: "Timeout expired" in SSMS

**Causes**:
- Incorrect server name format (use comma: `localhost,11433`)
- Port forward not running
- Wrong credentials

**Fix**:
1. Verify port forward syntax: `localhost,11433` (comma, not colon)
2. Check terminal with port forward is still running
3. Test with `telnet localhost 11433` (should connect if port forward works)

### "Target Not in VPC" Error

**Error**: "The specified target is not in a VPC"

**Cause**: Trying to use `AWS-StartPortForwardingSessionToRemoteHost` for internet hosts

**Fix**: This document only works for private VPC resources. For internet hosts, use NAT Gateway or proxy.

## Advanced Tips

### Persistent Port Forwarding with AutoSSH

On Linux/Mac, keep port forward alive automatically:

```bash
# Install autossh
# Mac: brew install autossh
# Linux: sudo apt install autossh

# Create wrapper script
cat > ~/ssm-port-forward-rds.sh << 'EOF'
#!/bin/bash
aws ssm start-session \
  --target $INSTANCE_ID \
  --region us-east-2 \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"portNumber":["1433"],"localPortNumber":["11433"],"host":["'$RDS_ENDPOINT'"]}'
EOF

chmod +x ~/ssm-port-forward-rds.sh

# Run with autossh (auto-reconnect)
autossh -M 0 -f ~/ssm-port-forward-rds.sh
```

### Multi-Session: EC2 + RDS Simultaneously

Open two terminals:

**Terminal 1** (EC2 shell):
```bash
aws ssm start-session --target $INSTANCE_ID --region us-east-2
```

**Terminal 2** (RDS port forward):
```bash
aws ssm start-session \
  --target $INSTANCE_ID \
  --region us-east-2 \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"portNumber":["1433"],"localPortNumber":["11433"],"host":["'$RDS_ENDPOINT'"]}'
```

Now you can run commands on EC2 while SSMS is connected to RDS.

### Scripting Database Tasks

PowerShell script to run SQL via port forward:

```powershell
# setup-port-forward-and-query.ps1
$INSTANCE_ID = (terraform output -raw instance_id)
$RDS_ENDPOINT = (terraform output -raw rds_endpoint)

# Start port forward in background (PowerShell 7+)
$portForwardJob = Start-Job -ScriptBlock {
    aws ssm start-session `
      --target $using:INSTANCE_ID `
      --region us-east-2 `
      --document-name AWS-StartPortForwardingSessionToRemoteHost `
      --parameters ('{"portNumber":["1433"],"localPortNumber":["11433"],"host":["' + $using:RDS_ENDPOINT + '"]}')
}

# Wait for port to be ready
Start-Sleep -Seconds 5

# Run SQL query
$query = "SELECT @@VERSION"
Invoke-Sqlcmd -ServerInstance "localhost,11433" -Username admin -Password "YourPassword" -Query $query

# Cleanup
Stop-Job $portForwardJob
Remove-Job $portForwardJob
```

## Security Notes

1. **No Inbound Ports Open**: EC2 has no public IP and no inbound security group rules. All access via SSM.
2. **IAM Session Permissions**: SSM sessions are audited in CloudTrail. Your IAM username is logged.
3. **Session Recording**: Enable Session Manager session logging to S3/CloudWatch for compliance.
4. **MFA Enforcement**: Consider enforcing MFA for SSM session initiation via IAM policy conditions.

## Quick Reference Card

```bash
# Get instance ID
export INSTANCE_ID=$(cd terraform && terraform output -raw instance_id)

# Get RDS endpoint (when provisioned)
export RDS_ENDPOINT=$(cd terraform && terraform output -raw rds_endpoint)

# Interactive shell
aws ssm start-session --target $INSTANCE_ID --region us-east-2

# Port forward: RDP
aws ssm start-session \
  --target $INSTANCE_ID \
  --region us-east-2 \
  --document-name AWS-StartPortForwardingSession \
  --parameters "portNumber=3389,localPortNumber=13389"

# Port forward: RDS SQL Server
aws ssm start-session \
  --target $INSTANCE_ID \
  --region us-east-2 \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"portNumber\":[\"1433\"],\"localPortNumber\":[\"11433\"],\"host\":[\"$RDS_ENDPOINT\"]}"

# SSMS connection string (after port forward)
# Server: localhost,11433
# Auth: SQL Server Authentication
# User: admin
```

## Additional Resources

- [AWS Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [Port Forwarding with Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html#sessions-start-port-forwarding)
- [RDS Custom for SQL Server](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/custom-setup-sqlserver.html)
- [SSMS Download](https://aka.ms/ssmsfullsetup)
- [SSM Plugin Installation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
