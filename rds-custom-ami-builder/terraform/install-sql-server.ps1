<powershell>
# RDS Custom for SQL Server - AMI Builder Installation Script
# This script installs and configures SQL Server for RDS Custom compatibility

$ErrorActionPreference = "Stop"
$LogFile = "C:\RDSCustom\install.log"
$Region = "${region}"
$S3Bucket = "${s3_media_bucket}"
$IsoKey = "${sql_iso_key}"
$CUKey = "${sql_cu_key}"
$SqlVersion = "${sql_version}"
$SqlEdition = "${sql_edition}"
$InstanceName = "${sql_instance_name}"
$Collation = "${sql_collation}"
$SAPasswordParam = "${sa_password_param}"

# Create directories
New-Item -ItemType Directory -Force -Path "C:\RDSCustom" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\SQLMedia" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\SQLInstall" | Out-Null

function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "$Timestamp - $Message"
    Add-Content -Path $LogFile -Value $LogMessage
    Write-Host $LogMessage
}

Write-Log "=========================================="
Write-Log "RDS Custom SQL Server AMI Builder Started"
Write-Log "=========================================="

# Retrieve SA password from SSM
Write-Log "Retrieving SA password from SSM Parameter Store..."
try {
    $SAPassword = (aws ssm get-parameter --name $SAPasswordParam --with-decryption --region $Region --query 'Parameter.Value' --output text)
    Write-Log "SA password retrieved successfully."
} catch {
    Write-Log "ERROR: Failed to retrieve SA password: $_"
    exit 1
}

# Download SQL Server ISO from S3
Write-Log "Downloading SQL Server ISO from S3..."
try {
    aws s3 cp "s3://$S3Bucket/$IsoKey" "C:\SQLMedia\SQLServer.iso" --region $Region
    Write-Log "SQL Server ISO downloaded successfully."
} catch {
    Write-Log "ERROR: Failed to download SQL Server ISO: $_"
    exit 1
}

# Download Cumulative Update from S3
Write-Log "Downloading SQL Server Cumulative Update from S3..."
try {
    aws s3 cp "s3://$S3Bucket/$CUKey" "C:\SQLMedia\SQLCU.exe" --region $Region
    Write-Log "Cumulative Update downloaded successfully."
} catch {
    Write-Log "ERROR: Failed to download Cumulative Update: $_"
    exit 1
}

# Mount ISO
Write-Log "Mounting SQL Server ISO..."
try {
    $MountResult = Mount-DiskImage -ImagePath "C:\SQLMedia\SQLServer.iso" -PassThru
    $DriveLetter = ($MountResult | Get-Volume).DriveLetter
    Write-Log "ISO mounted to drive $DriveLetter`:"
} catch {
    Write-Log "ERROR: Failed to mount ISO: $_"
    exit 1
}

# Install SQL Server
Write-Log "Installing SQL Server $SqlVersion $SqlEdition..."
Write-Log "This will take 20-30 minutes..."

$SetupPath = "$DriveLetter`:\setup.exe"
$ConfigFile = @"
[OPTIONS]
ACTION="Install"
QUIET="True"
IACCEPTSQLSERVERLICENSETERMS="True"
ENU="True"
UPDATEENABLED="False"
FEATURES=SQLENGINE,REPLICATION,FULLTEXT,CONN
INSTANCENAME="$InstanceName"
INSTANCEID="$InstanceName"
SQLSVCACCOUNT="NT AUTHORITY\SYSTEM"
SQLSYSADMINACCOUNTS="BUILTIN\Administrators"
AGTSVCACCOUNT="NT AUTHORITY\SYSTEM"
SECURITYMODE="SQL"
SAPWD="$SAPassword"
SQLCOLLATION="$Collation"
SQLBACKUPDIR="C:\SQLBackup"
SQLUSERDBDIR="C:\SQLData"
SQLUSERDBLOGDIR="C:\SQLLog"
SQLTEMPDBDIR="C:\SQLTemp"
SQLTEMPDBLOGDIR="C:\SQLTempLog"
TCPENABLED="1"
NPENABLED="0"
"@

$ConfigFile | Out-File -FilePath "C:\SQLInstall\ConfigurationFile.ini" -Encoding ASCII

try {
    $InstallProcess = Start-Process -FilePath $SetupPath -ArgumentList "/ConfigurationFile=C:\SQLInstall\ConfigurationFile.ini" -Wait -PassThru -NoNewWindow

    if ($InstallProcess.ExitCode -eq 0) {
        Write-Log "SQL Server installed successfully."
    } elseif ($InstallProcess.ExitCode -eq 3010) {
        Write-Log "SQL Server installed successfully (reboot required)."
    } else {
        Write-Log "ERROR: SQL Server installation failed with exit code: $($InstallProcess.ExitCode)"
        Write-Log "Check installation logs at: C:\Program Files\Microsoft SQL Server\*\Setup Bootstrap\Log\Summary.txt"
        exit 1
    }
} catch {
    Write-Log "ERROR: SQL Server installation exception: $_"
    exit 1
}

# Unmount ISO
Write-Log "Unmounting SQL Server ISO..."
Dismount-DiskImage -ImagePath "C:\SQLMedia\SQLServer.iso"

# Apply Cumulative Update
Write-Log "Applying SQL Server Cumulative Update..."
Write-Log "This will take 10-15 minutes..."

try {
    $CUProcess = Start-Process -FilePath "C:\SQLMedia\SQLCU.exe" -ArgumentList "/quiet", "/IAcceptSQLServerLicenseTerms", "/Action=Patch", "/AllInstances" -Wait -PassThru -NoNewWindow

    if ($CUProcess.ExitCode -eq 0 -or $CUProcess.ExitCode -eq 3010) {
        Write-Log "Cumulative Update applied successfully."
    } else {
        Write-Log "WARNING: Cumulative Update may have failed with exit code: $($CUProcess.ExitCode)"
        Write-Log "Continuing with RDS Custom configuration..."
    }
} catch {
    Write-Log "WARNING: Cumulative Update exception: $_"
    Write-Log "Continuing with RDS Custom configuration..."
}

# Configure SQL Server for RDS Custom
Write-Log "Configuring SQL Server for RDS Custom compatibility..."

# Enable TCP/IP and set port 1433
Write-Log "Configuring TCP/IP protocol..."
$SqlWmiManagement = [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')
$SMOWmiServer = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
$TCPProtocol = $SMOWmiServer.ServerInstances[$InstanceName].ServerProtocols['Tcp']
$TCPProtocol.IsEnabled = $true
$TCPProtocol.Alter()

$TCPIPAll = $TCPProtocol.IPAddresses['IPAll']
$TCPIPAll.IPAddressProperties['TcpPort'].Value = '1433'
$TCPIPAll.IPAddressProperties['TcpDynamicPorts'].Value = ''
$TCPIPAll.Alter()

Write-Log "TCP/IP protocol configured on port 1433."

# Configure SQL Server Agent
Write-Log "Configuring SQL Server Agent..."
Set-Service -Name "SQLSERVERAGENT" -StartupType Automatic
Start-Service -Name "SQLSERVERAGENT"
Write-Log "SQL Server Agent configured and started."

# Disable SQL Browser (not needed for RDS Custom)
Write-Log "Disabling SQL Browser..."
Stop-Service -Name "SQLBrowser" -Force -ErrorAction SilentlyContinue
Set-Service -Name "SQLBrowser" -StartupType Disabled
Write-Log "SQL Browser disabled."

# Configure Windows Firewall
Write-Log "Configuring Windows Firewall rules..."
New-NetFirewallRule -DisplayName "SQL Server" -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow -Profile Any
Write-Log "Firewall rules configured."

# Enable SQL Server audit logging
Write-Log "Configuring SQL Server audit logging..."
$SqlCmd = @"
USE master;
GO
EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'AuditLevel', REG_DWORD, 3;
GO
"@
Invoke-Sqlcmd -Query $SqlCmd -ServerInstance "localhost" -Username "sa" -Password $SAPassword

Write-Log "Audit logging configured."

# Restart SQL Server services
Write-Log "Restarting SQL Server services..."
Restart-Service -Name "MSSQLSERVER" -Force
Start-Sleep -Seconds 10
Restart-Service -Name "SQLSERVERAGENT" -Force
Write-Log "SQL Server services restarted."

# Verify installation
Write-Log "Verifying SQL Server installation..."
try {
    $VersionQuery = "SELECT @@VERSION AS Version"
    $Version = Invoke-Sqlcmd -Query $VersionQuery -ServerInstance "localhost" -Username "sa" -Password $SAPassword
    Write-Log "SQL Server Version: $($Version.Version)"
} catch {
    Write-Log "ERROR: Failed to verify SQL Server installation: $_"
    exit 1
}

# RDS Custom specific configurations
Write-Log "Applying RDS Custom specific configurations..."

# Set recommended registry settings for RDS Custom
Write-Log "Setting RDS Custom registry values..."
$RegPath = "HKLM:\SOFTWARE\Microsoft\MSSQLServer\MSSQLServer"
Set-ItemProperty -Path $RegPath -Name "LoginMode" -Value 2  # Mixed mode
Set-ItemProperty -Path $RegPath -Name "BackupDirectory" -Value "C:\SQLBackup"

Write-Log "Registry settings configured."

# Clean up installation files
Write-Log "Cleaning up installation files..."
Remove-Item -Path "C:\SQLMedia" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\SQLInstall" -Recurse -Force -ErrorAction SilentlyContinue
Write-Log "Cleanup completed."

# Prepare for Sysprep (EC2Launch v2)
Write-Log "Preparing instance for AMI creation..."

# Stop SQL Server services before sysprep
Write-Log "Stopping SQL Server services..."
Stop-Service -Name "SQLSERVERAGENT" -Force
Stop-Service -Name "MSSQLSERVER" -Force

# Run EC2Launch sysprep (for Windows Server 2016+)
Write-Log "Running EC2Launch sysprep..."
try {
    & "C:\ProgramData\Amazon\EC2Launch\Scripts\InitializeInstance.ps1" -Schedule
    Write-Log "EC2Launch sysprep scheduled."
} catch {
    Write-Log "WARNING: EC2Launch sysprep failed: $_"
}

Write-Log "=========================================="
Write-Log "RDS Custom SQL Server AMI Builder Complete"
Write-Log "=========================================="
Write-Log "Instance is ready for AMI creation."
Write-Log "Next steps:"
Write-Log "  1. Stop this instance"
Write-Log "  2. Create AMI from this instance"
Write-Log "  3. Create Custom Engine Version (CEV)"
Write-Log "  4. Deploy RDS Custom instance"

# Stop the instance (comment out if you want to review logs first)
# Write-Log "Stopping instance..."
# Stop-Computer -Force

</powershell>
