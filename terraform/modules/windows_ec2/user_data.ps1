<powershell>
# Configure logging
$LogFile = "C:\Windows\Temp\userdata.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $LogFile -Append
    Write-Host $Message
}

Write-Log "Starting UserData script for ${project_name}-${env}"

try {
    # Set timezone to Mountain Standard Time
    Write-Log "Setting timezone to Mountain Standard Time"
    Set-TimeZone -Id "Mountain Standard Time"

    # Install .NET Framework 3.5
    Write-Log "Installing .NET Framework 3.5"
    Install-WindowsFeature -Name NET-Framework-Core -ErrorAction Stop

    # Install Chocolatey
    Write-Log "Installing Chocolatey"
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

    # Refresh environment variables
    $env:ChocolateyInstall = Convert-Path "$((Get-Command choco).Path)\..\.."
    Import-Module "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
    refreshenv

    # Install SQL Server Management Studio (SSMS)
    Write-Log "Installing SQL Server Management Studio (SSMS)"
    choco install sql-server-management-studio -y --no-progress

    # Install Notepad++
    Write-Log "Installing Notepad++"
    choco install notepadplusplus -y --no-progress

    # Install .NET Framework 4.8.1
    Write-Log "Installing .NET Framework 4.8.1"
    choco install netfx-4.8.1-devpack -y --no-progress

    # Install Network Policy Server (NPS) role
    Write-Log "Installing Network Policy Server (NPS) role"
    Install-WindowsFeature -Name NPAS -IncludeManagementTools -ErrorAction Stop

    Write-Log "UserData script completed successfully"

} catch {
    Write-Log "ERROR: $_"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)"
    throw
}
</powershell>


