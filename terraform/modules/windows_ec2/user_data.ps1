<powershell>
# Windows Server 2022 Bootstrap Script
# Installs .NET Framework 3.5, 4.8.1, SSMS, Notepad++, and NPS role

$ErrorActionPreference = "Stop"
$LogFile = "C:\CloudInit\bootstrap.log"
$LogGroup = "${log_group_name}"
$Region = "${region}"

# Create log directory
New-Item -ItemType Directory -Force -Path "C:\CloudInit" | Out-Null

function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "$Timestamp - $Message"
    Add-Content -Path $LogFile -Value $LogMessage
    Write-Host $LogMessage
}

Write-Log "===== Starting Windows Server 2022 Bootstrap ====="

# Install CloudWatch Logs agent (optional, for log streaming)
try {
    Write-Log "Configuring CloudWatch Logs..."
    # Note: CloudWatch agent requires separate configuration file
    # For simplicity, using PowerShell logging to local file
} catch {
    Write-Log "WARNING: CloudWatch Logs setup failed: $_"
}

# Install .NET Framework 3.5 (includes 2.0 and 3.0)
try {
    Write-Log "Installing .NET Framework 3.5..."
    Install-WindowsFeature NET-Framework-Core -Source "\\path\to\sxs" -ErrorAction SilentlyContinue
    # Alternative: DISM with online source
    # DISM /Online /Enable-Feature /FeatureName:NetFx3 /All
    Write-Log ".NET Framework 3.5 installation initiated."
} catch {
    Write-Log "ERROR: .NET Framework 3.5 installation failed: $_"
}

# Install .NET Framework 4.8.1
try {
    Write-Log "Installing .NET Framework 4.8.1..."
    $Net48Url = "https://go.microsoft.com/fwlink/?linkid=2203306"
    $Net48Installer = "C:\CloudInit\ndp481-x64.exe"

    Invoke-WebRequest -Uri $Net48Url -OutFile $Net48Installer -UseBasicParsing
    Start-Process -FilePath $Net48Installer -ArgumentList "/q", "/norestart" -Wait -NoNewWindow

    Write-Log ".NET Framework 4.8.1 installed successfully."
} catch {
    Write-Log "ERROR: .NET Framework 4.8.1 installation failed: $_"
}

# Verify .NET installations
try {
    Write-Log "Verifying .NET installations..."
    $Net35 = Get-WindowsFeature NET-Framework-Core
    $Net48Key = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction SilentlyContinue

    Write-Log ".NET 3.5 Installed: $($Net35.Installed)"
    Write-Log ".NET 4.x Release: $($Net48Key.Release)"
} catch {
    Write-Log "WARNING: .NET verification incomplete: $_"
}

# Install Chocolatey
try {
    Write-Log "Installing Chocolatey package manager..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    Write-Log "Chocolatey installed successfully."
} catch {
    Write-Log "ERROR: Chocolatey installation failed: $_"
}

# Install SQL Server Management Studio (SSMS) via Chocolatey
try {
    Write-Log "Installing SQL Server Management Studio (SSMS)..."
    choco install sql-server-management-studio -y --no-progress --log-file="C:\CloudInit\choco-ssms.log"
    Write-Log "SSMS installed successfully."
} catch {
    Write-Log "ERROR: SSMS installation failed: $_"
}

# Install Notepad++
try {
    Write-Log "Installing Notepad++..."
    choco install notepadplusplus -y --no-progress --log-file="C:\CloudInit\choco-npp.log"
    Write-Log "Notepad++ installed successfully."
} catch {
    Write-Log "ERROR: Notepad++ installation failed: $_"
}

# Install Network Policy Server (NPS) role
try {
    Write-Log "Installing Network Policy Server (NPS) role..."
    Install-WindowsFeature NPAS -IncludeManagementTools

    # Enable NPS service
    Set-Service -Name IAS -StartupType Automatic
    Start-Service -Name IAS

    Write-Log "NPS role installed and service started."
} catch {
    Write-Log "ERROR: NPS installation failed: $_"
}

# Sanity check NPS
try {
    $NPSService = Get-Service -Name IAS -ErrorAction SilentlyContinue
    Write-Log "NPS Service Status: $($NPSService.Status)"
} catch {
    Write-Log "WARNING: NPS service check failed: $_"
}

# Environment variables for SQL media (for future use)
[Environment]::SetEnvironmentVariable("SQL_ISO_PATH", "s3://${s3_media_bucket}/media/SERVER_EVAL_x64FRE_en-us.iso", "Machine")
[Environment]::SetEnvironmentVariable("SQL_CU_PATH", "s3://${s3_media_bucket}/media/sqlserver2022-kb5041321-x64_1b40129fb51df67f28feb2a1ea139044c611b93f.exe", "Machine")

Write-Log "SQL Server media paths configured as environment variables."

# Optional: Download SQL media (commented out - no-op unless needed for RDS Custom AMI build)
# try {
#     Write-Log "Downloading SQL Server installation media..."
#     aws s3 cp s3://${s3_media_bucket}/media/SERVER_EVAL_x64FRE_en-us.iso C:\SQLMedia\SERVER_EVAL.iso
#     aws s3 cp s3://${s3_media_bucket}/media/sqlserver2022-kb5041321-x64_1b40129fb51df67f28feb2a1ea139044c611b93f.exe C:\SQLMedia\CU.exe
#     Write-Log "SQL Server media downloaded."
# } catch {
#     Write-Log "INFO: SQL Server media download skipped or failed: $_"
# }

Write-Log "===== Bootstrap Complete ====="
Write-Log "Review this log at: $LogFile"

# Optional: Signal completion to CloudFormation or other orchestration (if used)
# cfn-signal.exe -e 0 --stack ... --resource ... --region ...
</powershell>
