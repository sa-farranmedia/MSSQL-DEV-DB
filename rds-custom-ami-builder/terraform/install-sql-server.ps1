<powershell>
# SQL Server Installation Script for RDS Custom CEV
# CRITICAL: Uses $ for PowerShell variable escaping in templatefile

# Configure logging
$LogFile = "C:\Windows\Temp\sql-install.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append
    Write-Host $Message
}

Write-Log "=========================================="
Write-Log "SQL Server 2022 Developer Edition Install"
Write-Log "=========================================="

try {
    # ========================================
    # STEP 1: Install AWS PowerShell Modules
    # ========================================
    Write-Log "STEP 1: Installing AWS PowerShell modules"

    Install-PackageProvider -Name NuGet -Force -Scope AllUsers | Out-Null
    Write-Log "✓ NuGet package provider installed"

    Install-Module -Name AWS.Tools.S3 -Force -Scope AllUsers -ErrorAction Stop

    Write-Log "✓ AWS.Tools.S3 module installed"

    # ========================================
    # STEP 2: Download SQL Server Media from S3
    # ========================================
    Write-Log "STEP 2: Downloading SQL Server media from S3"

    $S3Bucket   = "${s3_bucket}"
    $IsoKey     = "${sql_iso_key}"
    $CuKey      = "${sql_cu_key}"
    $SaPassword = "${sa_password}"

    Write-Log "S3 Bucket: $S3Bucket"
    Write-Log "ISO Key: $IsoKey"
    Write-Log "CU Key: $CuKey"

    $WorkDir  = "C:\SQLInstall"
    $ISOPath  = Join-Path $WorkDir "SQLServer2022-DEV.iso"
    $CUPath   = Join-Path $WorkDir "SQLServer2022-CU.exe"

    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    Write-Log "✓ Created working directory: $WorkDir"

    Write-Log "Downloading SQL Server ISO..."
    Read-S3Object -BucketName $S3Bucket -Key $IsoKey -File $ISOPath -ErrorAction Stop
    Write-Log "✓ Downloaded ISO: $ISOPath"

    Write-Log "Downloading Cumulative Update..."
    Read-S3Object -BucketName $S3Bucket -Key $CuKey -File $CUPath -ErrorAction Stop
    Write-Log "✓ Downloaded CU: $CUPath"

    # ========================================
    # STEP 3: Mount ISO and Locate Setup
    # ========================================
    Write-Log "STEP 3: Mounting SQL Server ISO"

    $img = Mount-DiskImage -ImagePath $ISOPath -PassThru -ErrorAction Stop
    Write-Log "✓ ISO mounted"

    # Use $ for PowerShell variables (templatefile escaping)
    $DriveLetter = ($img | Get-Volume | Where-Object DriveLetter | Select-Object -First 1).DriveLetter
    Write-Log "✓ Drive letter: $${DriveLetter}"

    $SetupPath = "$${DriveLetter}:\setup.exe"
    Write-Log "✓ Setup path: $SetupPath"

    # ========================================
    # STEP 4: Create Configuration File
    # ========================================
    Write-Log "STEP 4: Creating SQL Server configuration file"

    $IniPath = Join-Path $WorkDir "ConfigurationFile.ini"

    # CRITICAL: ConfigurationFile.ini for RDS Custom requirements
    @"
[OPTIONS]
ACTION="Install"
FEATURES=SQLENGINE,REPLICATION,FULLTEXT
INSTANCENAME="MSSQLSERVER"
INSTANCEID="MSSQLSERVER"
SQLSVCACCOUNT="NT Service\MSSQLSERVER"
AGTSVCACCOUNT="NT Service\SQLSERVERAGENT"
SQLSVCSTARTUPTYPE="Manual"
AGTSVCSTARTUPTYPE="Manual"
BROWSERSVCSTARTUPTYPE="Disabled"
SECURITYMODE="SQL"
IACCEPTSQLSERVERLICENSETERMS="True"
"@ | Set-Content -Path $IniPath -Encoding ASCII

    Write-Log "✓ Configuration file created: $IniPath"

    # ========================================
    # STEP 5: Install SQL Server
    # ========================================
    Write-Log "STEP 5: Installing SQL Server 2022 Developer Edition"
    Write-Log "This will take 15-20 minutes..."

    # CRITICAL: SA password passed on command line, NOT in INI file
    $InstallArgs = @(
        "/q",
        "/ACTION=Install",
        "/IACCEPTSQLSERVERLICENSETERMS",
        "/ConfigurationFile=`"$IniPath`"",
        "/SAPWD=`"$${SaPassword}`""
    )

    Start-Process -FilePath $SetupPath -ArgumentList $InstallArgs -Wait -NoNewWindow -ErrorAction Stop
    Write-Log "✓ SQL Server installation completed"

    # ========================================
    # STEP 6: Apply Cumulative Update
    # ========================================
    Write-Log "STEP 6: Applying Cumulative Update"
    Write-Log "This will take 10-15 minutes..."

    $CUArgs = @(
        "/quiet",
        "/IAcceptSQLServerLicenseTerms",
        "/Action=Patch",
        "/AllInstances"
    )

    Start-Process -FilePath $CUPath -ArgumentList $CUArgs -Wait -NoNewWindow -ErrorAction Stop
    Write-Log "✓ Cumulative Update applied"

    # ========================================
    # STEP 7: Configure TCP/IP via Registry
    # ========================================
    Write-Log "STEP 7: Configuring TCP/IP on port 1433"

    # Stop SQL Server to modify registry
    Stop-Service MSSQLSERVER -Force -ErrorAction Stop
    Start-Sleep -Seconds 5
    Write-Log "✓ Stopped SQL Server service"

    # CRITICAL: Configure TCP/IP via REGISTRY (not SMO/WMI)
    $TCP = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQLServer\SuperSocketNetLib\Tcp"

    New-ItemProperty -Path $TCP -Name Enabled -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Log "✓ Enabled TCP/IP protocol"

    New-ItemProperty -Path "$TCP\IPAll" -Name TcpPort -Value "1433" -PropertyType String -Force | Out-Null
    Write-Log "✓ Set TCP port to 1433"

    New-ItemProperty -Path "$TCP\IPAll" -Name TcpDynamicPorts -Value "" -PropertyType String -Force | Out-Null
    Write-Log "✓ Disabled dynamic ports"

    # Start SQL Server with new settings
    Start-Service MSSQLSERVER -ErrorAction Stop
    Start-Sleep -Seconds 10
    Write-Log "✓ Started SQL Server service with TCP/IP enabled"

    # ========================================
    # STEP 8: Grant SYSTEM Sysadmin Role
    # ========================================
    Write-Log "STEP 8: Granting NT AUTHORITY\SYSTEM sysadmin role"

    # Install SqlServer PowerShell module
    Install-Module -Name SqlServer -Force -Scope AllUsers -ErrorAction Stop
    Import-Module SqlServer -ErrorAction Stop
    Write-Log "✓ SqlServer PowerShell module loaded"

    # Grant SYSTEM sysadmin (REQUIRED by RDS Custom)
    $GrantSystemQuery = @"
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'NT AUTHORITY\SYSTEM')
    CREATE LOGIN [NT AUTHORITY\SYSTEM] FROM WINDOWS;
EXEC sp_addsrvrolemember N'NT AUTHORITY\SYSTEM', N'sysadmin';
"@

    Invoke-Sqlcmd -ServerInstance localhost -Username sa -Password $${SaPassword} -Query $GrantSystemQuery -ErrorAction Stop
    Write-Log "✓ Granted NT AUTHORITY\SYSTEM sysadmin role"

    # ========================================
    # STEP 9: Set Services to Manual
    # ========================================
    Write-Log "STEP 9: Configuring service startup types"

    Set-Service MSSQLSERVER -StartupType Manual -ErrorAction Stop
    Write-Log "✓ Set MSSQLSERVER startup type to Manual"

    Set-Service SQLSERVERAGENT -StartupType Manual -ErrorAction SilentlyContinue
    Write-Log "✓ Set SQLSERVERAGENT startup type to Manual"

    # Stop services for AMI creation
    Stop-Service SQLSERVERAGENT -ErrorAction SilentlyContinue
    Write-Log "✓ Stopped SQLSERVERAGENT"

    Stop-Service MSSQLSERVER -ErrorAction Stop
    Write-Log "✓ Stopped MSSQLSERVER"

    # ========================================
    # STEP 10: Disable SQL Browser
    # ========================================
    Write-Log "STEP 10: Disabling SQL Browser service"

    Set-Service SQLBrowser -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service SQLBrowser -ErrorAction SilentlyContinue
    Write-Log "✓ SQL Browser disabled"

    # ========================================
    # STEP 11: EC2Launch v2 Sysprep
    # ========================================
    Write-Log "STEP 11: Running EC2Launch v2 sysprep with shutdown"

    $ec2launch = "$env:ProgramFiles\Amazon\EC2Launch\EC2Launch.exe"

    if (Test-Path $ec2launch) {
        Write-Log "Running sysprep: $ec2launch sysprep --shutdown"
        & $ec2launch sysprep --shutdown
        Write-Log "✓ Sysprep initiated - instance will shutdown"
    } else {
        Write-Log "WARNING: EC2Launch not found at $ec2launch"
        Write-Log "Manual sysprep required before creating AMI"
    }

    Write-Log "=========================================="
    Write-Log "SQL Server installation COMPLETED"
    Write-Log "=========================================="

} catch {
    Write-Log "=========================================="
    Write-Log "ERROR: SQL Server installation FAILED"
    Write-Log "Error: $_"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)"
    Write-Log "=========================================="
    throw
}
</powershell>


