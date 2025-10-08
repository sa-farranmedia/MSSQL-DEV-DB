#!/usr/bin/env bash
# Build SQL Server 2022 Developer with CU19 for RDS Custom
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required. Install jq and re-run." >&2
  exit 1
fi

# ---------- inputs ----------
DEFAULT_REGION="$(aws configure get region 2>/dev/null)"
DEFAULT_REGION="${DEFAULT_REGION:-us-east-2}"
read -rp "AWS region [${DEFAULT_REGION}]: " REGION
REGION="${REGION:-$DEFAULT_REGION}"

read -rp "EC2 Instance ID: " INSTANCE_ID
if [[ -z "${INSTANCE_ID}" ]]; then echo "Instance ID is required"; exit 1; fi

STAMP="$(date +%Y%m%d-%H%M%S)"
read -rp "AMI name [ws2019-sql2022-cu19-dev-${STAMP}]: " AMI_NAME
AMI_NAME="${AMI_NAME:-ws2019-sql2022-cu19-dev-${STAMP}}"

# SQL Server media locations
DEFAULT_SQL_ISO_URI="s3://dev-sqlserver-supportfiles-backups-and-iso-files/media/SQLServer2022-x64-ENU-Dev.iso"
read -rp "SQL Server 2022 Developer ISO S3 URI [${DEFAULT_SQL_ISO_URI}]: " SQL_ISO_URI
SQL_ISO_URI="${SQL_ISO_URI:-$DEFAULT_SQL_ISO_URI}"

DEFAULT_CU_URI="s3://dev-sqlserver-supportfiles-backups-and-iso-files/media/sqlserver2022-kb5041321-x64_1b40129fb51df67f28feb2a1ea139044c611b93f.exe"
read -rp "SQL Server 2022 CU19 S3 URI [${DEFAULT_CU_URI}]: " CU_URI
CU_URI="${CU_URI:-$DEFAULT_CU_URI}"

# Parse S3 bucket/key
URI_NO_PREFIX="${SQL_ISO_URI#s3://}"
SQL_BUCKET="${URI_NO_PREFIX%%/*}"
SQL_KEY="${URI_NO_PREFIX#*/}"

CU_URI_NO_PREFIX="${CU_URI#s3://}"
CU_BUCKET="${CU_URI_NO_PREFIX%%/*}"
CU_KEY="${CU_URI_NO_PREFIX#*/}"

echo "=========================================="
echo "Building SQL Server 2022 Developer CU19 AMI"
echo "ISO: $SQL_ISO_URI"
echo "CU:  $CU_URI"
echo "=========================================="

# Grant S3 access
INSTANCE_PROFILE=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' --output text 2>/dev/null || echo "")

if [[ -z "$INSTANCE_PROFILE" || "$INSTANCE_PROFILE" == "None" ]]; then
  echo "ERROR: Instance must have an IAM instance profile with S3 read access"
  exit 1
fi

# ---------- Main installation script ----------
echo "Installing SQL Server 2022 Developer + CU19..."

TMP_PS="$(mktemp)"
cat > "$TMP_PS" <<'PSEOF'
$ErrorActionPreference="Stop"
$ProgressPreference="SilentlyContinue"

Write-Host "=== RDS Custom SQL Server 2022 Developer CU19 Installation ==="

# Inputs from bash
$S3Bucket = "__BUCKET__"
$S3Key    = "__KEY__"
$CUBucket = "__CU_BUCKET__"
$CUKey    = "__CU_KEY__"
$Region   = "__REGION__"

$WorkDir = "C:\SQLInstall"
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

# Check if SQL Server is already installed
$existingInstall = Get-Service MSSQLSERVER -ErrorAction SilentlyContinue
if ($existingInstall) {
    Write-Host "SQL Server already installed, checking version..."
    $regPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQLServer\CurrentVersion"
    if (Test-Path $regPath) {
        $currentVersion = (Get-ItemProperty -Path $regPath).CurrentVersion
        Write-Host "Current version: $currentVersion"

        if ($currentVersion -eq "16.00.4195.2") {
            Write-Host "✓ CU19 (16.00.4195.2) already installed, skipping installation"
            exit 0
        } else {
            Write-Host "Different version found, will upgrade to CU19"
            # Stop services before upgrade
            Stop-Service SQLSERVERAGENT -Force -ErrorAction SilentlyContinue
            Stop-Service MSSQLSERVER -Force -ErrorAction SilentlyContinue
        }
    }
}

# 1. Install EC2Launch v2 (CRITICAL for RDS Custom)
Write-Host "Installing EC2Launch v2..."
$ec2LaunchUrl = "https://s3.amazonaws.com/amazon-ec2launch-v2/windows/amd64/latest/AmazonEC2Launch.msi"
$ec2LaunchMsi = Join-Path $WorkDir "AmazonEC2Launch.msi"
Invoke-WebRequest -Uri $ec2LaunchUrl -OutFile $ec2LaunchMsi -UseBasicParsing -TimeoutSec 600
Start-Process msiexec.exe -ArgumentList "/i `"$ec2LaunchMsi`" /qn" -Wait
Start-Sleep -Seconds 10
Write-Host "✓ EC2Launch v2 installed"

# 2. Ensure AWS CLI
Write-Host "Ensuring AWS CLI..."
$aws = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
if (-not (Test-Path $aws)) {
  $awsMsi = Join-Path $WorkDir "AWSCLIV2.msi"
  Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile $awsMsi -UseBasicParsing
  Start-Process msiexec.exe -ArgumentList "/i `"$awsMsi`" /qn" -Wait
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}
Write-Host "✓ AWS CLI ready"

# 3. Install .NET Framework 4.8 (REQUIRED for SQL Server)
Write-Host "Checking .NET Framework..."
$dotRel = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction SilentlyContinue).Release
if ($null -eq $dotRel -or $dotRel -lt 528040) {
  Write-Host "Installing .NET Framework 4.8..."
  $dot48 = Join-Path $WorkDir "ndp48-x86-x64-allos-enu.exe"
  Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=2088631" -OutFile $dot48 -UseBasicParsing
  $dotProc = Start-Process -FilePath $dot48 -ArgumentList "/q /norestart" -Wait -PassThru
  if ($dotProc.ExitCode -ne 0 -and $dotProc.ExitCode -ne 3010) {
    throw ".NET Framework 4.8 installation failed with exit code: $($dotProc.ExitCode)"
  }
  Write-Host "✓ .NET Framework 4.8 installed"

  # Verify installation
  $dotRel = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction SilentlyContinue).Release
  if ($dotRel -lt 528040) {
    throw ".NET Framework 4.8 installation failed. Release key: $dotRel (expected >= 528040)"
  }
} else {
  Write-Host "✓ .NET Framework 4.8 already present"
}

# Only install SQL Server if not already present
if (-not $existingInstall) {
    # 4. Download SQL Server ISO
    Write-Host "Downloading SQL Server ISO..."
    $isoPath = Join-Path $WorkDir "SQLServer.iso"
    & $aws s3 cp "s3://$S3Bucket/$S3Key" $isoPath --region $Region --no-progress
    if (-not (Test-Path $isoPath)) { throw "Failed to download SQL Server ISO" }
    Write-Host "✓ ISO downloaded"

    # 5. Mount ISO
    Write-Host "Mounting ISO..."
    $img = Mount-DiskImage -ImagePath $isoPath -PassThru
    Start-Sleep -Seconds 5
    $driveLetter = (Get-Volume -DiskImage $img).DriveLetter
    $setupPath = "$($driveLetter):\setup.exe"
    Write-Host "✓ ISO mounted at ${driveLetter}:"

    if (-not (Test-Path $setupPath)) { throw "setup.exe not found at $setupPath" }

    # 6. Install SQL Server 2022 RTM (REQUIRED settings for RDS Custom)
    Write-Host "Installing SQL Server 2022 RTM (this takes 10-15 minutes)..."

    $setupArgs = @(
        "/Q"
        "/ACTION=Install"
        "/IACCEPTSQLSERVERLICENSETERMS"
        "/FEATURES=SQLENGINE"
        "/INSTANCENAME=MSSQLSERVER"
        "/INSTANCEID=MSSQLSERVER"
        "/SQLSVCACCOUNT=`"NT Service\MSSQLSERVER`""
        "/AGTSVCACCOUNT=`"NT Service\SQLSERVERAGENT`""
        "/SQLSVCSTARTUPTYPE=Manual"
        "/AGTSVCSTARTUPTYPE=Manual"
        "/BROWSERSVCSTARTUPTYPE=Disabled"
        "/SQLSYSADMINACCOUNTS=`"NT AUTHORITY\SYSTEM`""
        "/UPDATEENABLED=False"
        "/INDICATEPROGRESS"
    )

    $process = Start-Process -FilePath $setupPath -ArgumentList $setupArgs -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        $logRoot = "C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\Log"
        Write-Host "SQL setup failed with exit code: $($process.ExitCode)"

        if (Test-Path $logRoot) {
            $latestLogDir = Get-ChildItem -Path $logRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latestLogDir) {
                $summaryLog = Join-Path $latestLogDir.FullName "Summary.txt"
                if (Test-Path $summaryLog) {
                    Write-Host "--- Summary.txt (last 100 lines) ---"
                    Get-Content $summaryLog -ErrorAction SilentlyContinue | Select-Object -Last 100
                }
            }
        }
        throw "SQL Server installation failed"
    }
    Write-Host "✓ SQL Server RTM installed"

    # 7. Unmount ISO
    Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
    Remove-Item $isoPath -Force -ErrorAction SilentlyContinue
}

# 8. Download Cumulative Update
Write-Host "Downloading SQL Server CU19..."
$cuPath = Join-Path $WorkDir "SQLServer-CU19.exe"

# Check if CU19 is already installed before downloading
$setupPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.MSSQLSERVER\Setup"
$sqlservrPath = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Binn\sqlservr.exe"
$alreadyInstalled = $false

if (Test-Path $setupPath) {
    $currentPatchLevel = (Get-ItemProperty -Path $setupPath -ErrorAction SilentlyContinue).PatchLevel
    if ($currentPatchLevel -eq "16.00.4195.2" -or $currentPatchLevel -eq "16.0.4195.2") {
        Write-Host "✓ CU19 already installed (PatchLevel: $currentPatchLevel), skipping CU installation"
        $alreadyInstalled = $true
    }
}

# Double-check with file version
if (-not $alreadyInstalled -and (Test-Path $sqlservrPath)) {
    $fileInfo = Get-Item $sqlservrPath
    if ($fileInfo.VersionInfo.ProductVersion -eq "16.0.4195.2") {
        Write-Host "✓ CU19 already installed (File version: 16.0.4195.2), skipping CU installation"
        $alreadyInstalled = $true
    }
}

if (-not $alreadyInstalled) {
    & $aws s3 cp "s3://$CUBucket/$CUKey" $cuPath --region $Region --no-progress
    if (-not (Test-Path $cuPath)) { throw "Failed to download CU19" }
    Write-Host "✓ CU19 downloaded"
} else {
    Write-Host "Skipping CU download and installation - already at correct version"
    # Jump directly to TCP/IP configuration
    $versionAfter = "16.00.4195.2"
}

# 9. Check SQL Server version BEFORE CU (only if not already installed)
if (-not $alreadyInstalled) {
    Write-Host "Checking SQL Server version before CU..."
    $regPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQLServer\CurrentVersion"
    $setupPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.MSSQLSERVER\Setup"

    $versionBefore = $null
    if (Test-Path $setupPath) {
        $setupProps = Get-ItemProperty $setupPath
        $versionBefore = $setupProps.PatchLevel
        Write-Host "Version before CU (PatchLevel): $versionBefore"
    } elseif (Test-Path $regPath) {
        $versionBefore = (Get-ItemProperty -Path $regPath).CurrentVersion
        Write-Host "Version before CU (CurrentVersion): $versionBefore"
    }

    # 10. START services before CU application (CRITICAL - CU needs running services)
    Write-Host "Starting SQL Server services for CU installation..."
    Start-Service MSSQLSERVER -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 10
    Start-Service SQLSERVERAGENT -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    Write-Host "✓ Services started"

# Diagnostic: Verify SQL Server is detectable
Write-Host ""
Write-Host "=== Pre-CU Diagnostics ==="
Write-Host "SQL Server Service Status:"
Get-Service | Where-Object { $_.Name -like "MSSQL*" -or $_.Name -like "SQLServer*" } | Format-Table Name, Status, StartType -AutoSize

Write-Host "SQL Server Registry Keys:"
$sqlRegPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server"
if (Test-Path $sqlRegPath) {
    Write-Host "Found SQL Server registry at: $sqlRegPath"

    # Check instance names
    $instancePath = "$sqlRegPath\Instance Names\SQL"
    if (Test-Path $instancePath) {
        Write-Host "Registered SQL instances:"
        $instances = Get-ItemProperty $instancePath -ErrorAction SilentlyContinue
        $instances.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
            Write-Host "  - $($_.Name) = $($_.Value)"
        }
    } else {
        Write-Host "WARNING: No instances registered at $instancePath"
    }

    # Check installed instances
    $installedPath = "$sqlRegPath\InstalledInstances"
    if (Test-Path $installedPath) {
        $installed = Get-ItemProperty $installedPath -ErrorAction SilentlyContinue
        Write-Host "Installed instances from registry:"
        $installed.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
            Write-Host "  - $($_.Value)"
        }
    }
}

Write-Host "Installed SQL Server Version Info:"
$verPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.MSSQLSERVER\Setup"
$sqlservrPath = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Binn\sqlservr.exe"

if (Test-Path $verPath) {
    $setupProps = Get-ItemProperty $verPath
    Write-Host "  Version: $($setupProps.Version)"
    Write-Host "  Edition: $($setupProps.Edition)"
    Write-Host "  PatchLevel: $($setupProps.PatchLevel)"
    Write-Host "  FeatureList: $($setupProps.FeatureList)"
    Write-Host "  ProductID: $($setupProps.ProductID)"
} else {
    Write-Host "WARNING: Setup registry path not found at $verPath"
}

# Check if sqlservr.exe exists
$sqlservrPath = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Binn\sqlservr.exe"
if (Test-Path $sqlservrPath) {
    $fileInfo = Get-Item $sqlservrPath
    Write-Host "sqlservr.exe found:"
    Write-Host "  Path: $sqlservrPath"
    Write-Host "  Version: $($fileInfo.VersionInfo.FileVersion)"
    Write-Host "  Product Version: $($fileInfo.VersionInfo.ProductVersion)"
} else {
    Write-Host "ERROR: sqlservr.exe not found at $sqlservrPath"
}

Write-Host "==========================="
Write-Host ""

# 11. Apply Cumulative Update 19 (CRITICAL - brings to 16.00.4195.2)
Write-Host "Applying SQL Server 2022 CU19 (this takes 5-10 minutes)..."
Write-Host "NOTE: CU installer needs SQL Server running to detect and patch properly"

# First, try to extract the CU to see if it helps with detection
Write-Host "Extracting CU19 package..."
$cuExtractPath = Join-Path $WorkDir "CU19Extract"
if (Test-Path $cuExtractPath) {
    Remove-Item $cuExtractPath -Recurse -Force
}
New-Item -ItemType Directory -Path $cuExtractPath -Force | Out-Null

# Extract with /x parameter
$extractArgs = "/x:`"$cuExtractPath`" /quiet"
Write-Host "Running: $cuPath $extractArgs"
$extractProc = Start-Process -FilePath $cuPath -ArgumentList $extractArgs -Wait -PassThru -NoNewWindow
Write-Host "Extract exit code: $($extractProc.ExitCode)"

Start-Sleep -Seconds 5

# Look for setup.exe in the extracted files
$setupExe = Get-ChildItem -Path $cuExtractPath -Filter "setup.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

if ($setupExe) {
    Write-Host "Found CU setup.exe at: $($setupExe.FullName)"
    $cuExecutable = $setupExe.FullName
} else {
    Write-Host "Setup.exe not found in extracted files, using original exe"
    $cuExecutable = $cuPath
}

# Build CU installation arguments - be VERY explicit
$cuArgs = @(
    "/quiet"
    "/IAcceptSQLServerLicenseTerms"
    "/Action=Patch"
    "/InstanceName=MSSQLSERVER"
)

Write-Host "Running CU installation with explicit instance name..."
Write-Host "Command: $cuExecutable $($cuArgs -join ' ')"

$cuProcess = Start-Process -FilePath $cuExecutable -ArgumentList $cuArgs -Wait -PassThru -NoNewWindow
$cuExitCode = $cuProcess.ExitCode

Write-Host "CU19 installation completed with exit code: $cuExitCode"

# Always check logs to understand what happened
$cuLogDir = "C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\Log"
if (Test-Path $cuLogDir) {
    $latestCuLog = Get-ChildItem -Path $cuLogDir -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestCuLog) {
        Write-Host ""
        Write-Host "=== CU Installation Logs ==="
        Write-Host "Log directory: $($latestCuLog.FullName)"

        $cuSummary = Join-Path $latestCuLog.FullName "Summary.txt"
        if (Test-Path $cuSummary) {
            Write-Host "--- CU Summary.txt (last 50 lines) ---"
            Get-Content $cuSummary -ErrorAction SilentlyContinue | Select-Object -Last 50
        }

        # Look for specific error patterns in Detail.txt
        $cuDetail = Join-Path $latestCuLog.FullName "Detail.txt"
        if (Test-Path $cuDetail) {
            $detailContent = Get-Content $cuDetail -ErrorAction SilentlyContinue

            # Check for common issues
            $noopError = $detailContent | Select-String "PatchNoopException"
            $notFoundError = $detailContent | Select-String "No SQL Server instances or shared features can be updated"

            if ($noopError) {
                Write-Host ""
                Write-Host "⚠ WARNING: CU reported 'PatchNoopException' - this means it couldn't find SQL Server to patch!"
                Write-Host "--- Relevant Detail.txt lines ---"
                Get-Content $cuDetail -ErrorAction SilentlyContinue | Select-String -Pattern "PatchNoop|No features were updated|not be installed" -Context 2,2
            }

            if ($notFoundError) {
                Write-Host ""
                Write-Host "⚠ WARNING: CU couldn't find SQL Server instances!"
                Write-Host "--- Relevant Detail.txt lines ---"
                Get-Content $cuDetail -ErrorAction SilentlyContinue | Select-String -Pattern "No SQL Server instances" -Context 2,2
            }

            Write-Host ""
            Write-Host "--- CU Detail.txt (last 50 lines) ---"
            Get-Content $cuDetail -ErrorAction SilentlyContinue | Select-Object -Last 50
        }

        Write-Host "==========================="
        Write-Host ""
    }
}

# Check what the CU thinks it did
Write-Host "Post-CU Registry Check:"
if (Test-Path $verPath) {
    $postCuProps = Get-ItemProperty $verPath
    Write-Host "  Version: $($postCuProps.Version)"
    Write-Host "  PatchLevel: $($postCuProps.PatchLevel)"
}

# Check file version
if (Test-Path $sqlservrPath) {
    $postCuFile = Get-Item $sqlservrPath
    Write-Host "  sqlservr.exe FileVersion: $($postCuFile.VersionInfo.FileVersion)"
}
Write-Host ""

# Exit codes: 0 = success, 3010 = success but reboot required
if ($cuExitCode -ne 0 -and $cuExitCode -ne 3010) {
    Write-Host "ERROR: CU19 installation failed with exit code: $cuExitCode"
    throw "CU19 installation failed"
}

if ($cuExitCode -eq 3010) {
    Write-Host "⚠ CU19 requires a reboot to complete installation"
    Write-Host "⚠ REBOOT_REQUIRED flag set - bash script will handle reboot"
}

Write-Host "✓ CU19 applied (exit code: $cuExitCode)"

# 12. Verify SQL Server version AFTER CU (CRITICAL)
Write-Host "Verifying SQL Server version after CU..."
Start-Sleep -Seconds 10

$versionAfter = $null
$maxRetries = 5
$retryCount = 0

while ($retryCount -lt $maxRetries) {
    # Check PatchLevel from Setup registry (more reliable than CurrentVersion)
    if (Test-Path $setupPath) {
        $versionAfter = (Get-ItemProperty -Path $setupPath -ErrorAction SilentlyContinue).PatchLevel

        if ($versionAfter -eq "16.00.4195.2" -or $versionAfter -eq "16.0.4195.2") {
            Write-Host "✓ Version verified: $versionAfter (CU19 - exact match)"
            break
        } elseif ($versionAfter -eq $versionBefore) {
            Write-Host "Version unchanged after CU installation (attempt $($retryCount + 1)/$maxRetries)"
            Write-Host "Current: $versionAfter"

            # If this is the first retry and version hasn't changed, try one more aggressive approach
            if ($retryCount -eq 0) {
                Write-Host ""
                Write-Host "⚠ Attempting alternative CU installation method..."
                Write-Host "Stopping SQL Server, applying CU, then starting..."

                Stop-Service MSSQLSERVER -Force -ErrorAction SilentlyContinue
                Stop-Service SQLSERVERAGENT -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 5

                # Try running CU again with different parameters
                $retryArgs = @(
                    "/quiet"
                    "/IAcceptSQLServerLicenseTerms"
                    "/Action=Patch"
                    "/AllInstances"
                )

                Write-Host "Retry command: $cuExecutable $($retryArgs -join ' ')"
                $retryProcess = Start-Process -FilePath $cuExecutable -ArgumentList $retryArgs -Wait -PassThru -NoNewWindow
                Write-Host "Retry exit code: $($retryProcess.ExitCode)"

                Start-Service MSSQLSERVER -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 10
            }

            $retryCount++
            Start-Sleep -Seconds 10
        } else {
            Write-Host "Version after CU: $versionAfter"
            break
        }
    } else {
        Write-Warning "Setup registry path not found (attempt $($retryCount + 1)/$maxRetries)"
        $retryCount++
        Start-Sleep -Seconds 10
    }
}

# Also verify the actual binary file version
$sqlservrPath = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Binn\sqlservr.exe"
if (Test-Path $sqlservrPath) {
    $fileInfo = Get-Item $sqlservrPath
    $fileVersion = $fileInfo.VersionInfo.ProductVersion
    Write-Host "sqlservr.exe Product Version: $fileVersion"

    # If PatchLevel shows CU19 and file version shows CU19, we're good
    if ($fileVersion -eq "16.0.4195.2" -and ($versionAfter -eq "16.00.4195.2" -or $versionAfter -eq "16.0.4195.2")) {
        Write-Host "✓ Binary file version matches PatchLevel - CU19 is properly installed"
        $versionAfter = "16.00.4195.2"  # Normalize for final check
    }
}

if ($versionAfter -ne "16.00.4195.2" -and $versionAfter -ne "16.0.4195.2") {
    Write-Host ""
    Write-Host "============================================"
    Write-Host "ERROR: CU19 VERSION MISMATCH!"
    Write-Host "Expected: 16.00.4195.2 (exact)"
    Write-Host "Found:    $versionAfter"
    Write-Host "============================================"
    Write-Host ""
    Write-Host "This will cause RDS Custom CEV creation to FAIL."
    Write-Host ""
    Write-Host "Possible causes:"
    Write-Host "1. Wrong CU file - verify KB5054531 is the correct Developer edition CU"
    Write-Host "2. CU file is corrupted - re-download from Microsoft"
    Write-Host "3. SQL Server installation has issues preventing CU detection"
    Write-Host ""
    Write-Host "To debug:"
    Write-Host "- Check logs at: C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\Log"
    Write-Host "- Verify S3 CU file matches official Microsoft download"
    Write-Host "- Check if SQL Server services are running"
    Write-Host ""
    throw "Version verification failed - CU19 not properly installed"
}
} # End of CU installation block (if not already installed)

# 13. Remove CU installer
if (-not $alreadyInstalled) {
    Remove-Item $cuPath -Force -ErrorAction SilentlyContinue
}

# Final version check regardless of whether CU was just installed or was already there
Write-Host ""
Write-Host "=== Final Version Verification ==="
$setupPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.MSSQLSERVER\Setup"
if (Test-Path $setupPath) {
    $finalPatchLevel = (Get-ItemProperty -Path $setupPath).PatchLevel
    Write-Host "Final PatchLevel: $finalPatchLevel"

    if ($finalPatchLevel -ne "16.00.4195.2" -and $finalPatchLevel -ne "16.0.4195.2") {
        throw "Final version check failed! Expected 16.00.4195.2 but found $finalPatchLevel"
    }
    $versionAfter = $finalPatchLevel
}

$sqlservrPath = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Binn\sqlservr.exe"
if (Test-Path $sqlservrPath) {
    $finalFileVersion = (Get-Item $sqlservrPath).VersionInfo.ProductVersion
    Write-Host "Final sqlservr.exe version: $finalFileVersion"

    if ($finalFileVersion -ne "16.0.4195.2") {
        throw "Final file version check failed! Expected 16.0.4195.2 but found $finalFileVersion"
    }
}
Write-Host "✓ All version checks passed - CU19 is properly installed"
Write-Host "==================================="
Write-Host ""

# 14. Configure TCP/IP via Registry (REQUIRED for RDS Custom)
Write-Host "Configuring TCP/IP..."
Stop-Service MSSQLSERVER -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

$tcpPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQLServer\SuperSocketNetLib\Tcp"
Set-ItemProperty -Path $tcpPath -Name Enabled -Value 1 -Force
Set-ItemProperty -Path "$tcpPath\IPAll" -Name TcpPort -Value "1433" -Force
Set-ItemProperty -Path "$tcpPath\IPAll" -Name TcpDynamicPorts -Value "" -Force
Write-Host "✓ TCP/IP enabled on port 1433"

# 15. Start SQL Server and verify SYSTEM has sysadmin
Write-Host "Starting SQL Server to verify configuration..."
Start-Service MSSQLSERVER
Start-Sleep -Seconds 15

$sqlcmd = "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe"
if (Test-Path $sqlcmd) {
    try {
        $result = & $sqlcmd -S localhost -E -Q "SELECT @@VERSION" -h -1 2>$null
        Write-Host "SQL Server version check:"
        $result | Where-Object { $_ -match "Microsoft SQL Server" } | ForEach-Object { Write-Host $_ }

        $sysadminCheck = & $sqlcmd -S localhost -E -Q "SELECT IS_SRVROLEMEMBER('sysadmin', 'NT AUTHORITY\SYSTEM')" -h -1 2>$null
        if ($sysadminCheck -match "1") {
            Write-Host "✓ NT AUTHORITY\SYSTEM has sysadmin role"
        } else {
            Write-Warning "NT AUTHORITY\SYSTEM may not have sysadmin role"
        }
    } catch {
        Write-Warning "Could not verify SQL Server configuration: $($_.Exception.Message)"
    }
}

# 16. Stop services for sysprep (REQUIRED)
Write-Host "Stopping services for sysprep..."
Stop-Service SQLSERVERAGENT -Force -ErrorAction SilentlyContinue
Stop-Service MSSQLSERVER -Force
Stop-Service SQLBrowser -Force -ErrorAction SilentlyContinue

# 17. Verify service startup types (REQUIRED)
$mssqlStartup   = (Get-Service MSSQLSERVER).StartType
$agentStartup   = (Get-Service SQLSERVERAGENT).StartType
$browserStartup = (Get-Service SQLBrowser).StartType

if ($mssqlStartup -ne "Manual")     { Write-Warning "MSSQLSERVER startup type is $mssqlStartup (should be Manual)" }
if ($agentStartup -ne "Manual")     { Write-Warning "SQLSERVERAGENT startup type is $agentStartup (should be Manual)" }
if ($browserStartup -ne "Disabled") { Write-Warning "SQLBrowser startup type is $browserStartup (should be Disabled)" }

Write-Host ""
Write-Host "=== SQL Server Installation Complete ==="
Write-Host "✓ Version: $versionAfter (CU19)"
Write-Host "✓ Default instance: MSSQLSERVER"
Write-Host "✓ Service accounts: NT Service accounts"
Write-Host "✓ Startup type: Manual"
Write-Host "✓ TCP/IP: Enabled on port 1433"
Write-Host "✓ SYSTEM: Has sysadmin"
Write-Host "✓ Browser: Disabled"
Write-Host "✓ EC2Launch v2: Installed"
Write-Host ""
Write-Host "Ready for sysprep!"
PSEOF

# Inject variables
TMP_PS_FILLED="$(mktemp)"
sed -e "s|__BUCKET__|$SQL_BUCKET|g" \
    -e "s|__KEY__|$SQL_KEY|g" \
    -e "s|__CU_BUCKET__|$CU_BUCKET|g" \
    -e "s|__CU_KEY__|$CU_KEY|g" \
    -e "s|__REGION__|$REGION|g" "$TMP_PS" > "$TMP_PS_FILLED"

PARAMS_FILE="$(mktemp)"
jq -Rs '{commands: [.]}' "$TMP_PS_FILLED" > "$PARAMS_FILE"

CMD_ID="$(aws ssm send-command \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunPowerShellScript" \
  --comment "Install SQL Server 2022 Developer CU19 for RDS Custom" \
  --cli-binary-format raw-in-base64-out \
  --parameters file://"$PARAMS_FILE" \
  --query 'Command.CommandId' --output text)"

echo "Waiting for SQL Server + CU19 installation (this takes 20-30 minutes)..."
for _ in {1..240}; do
  STATUS="$(aws ssm list-command-invocations --region "${REGION}" --command-id "$CMD_ID" --details \
    --query 'CommandInvocations[0].Status' --output text 2>/dev/null || echo "Pending")"

  if [[ "$STATUS" == "Success" ]]; then
    echo "✓ SQL Server + CU19 installed successfully"

    # Check if reboot is needed
    OUTPUT="$(aws ssm get-command-invocation \
      --region "${REGION}" \
      --command-id "$CMD_ID" \
      --instance-id "${INSTANCE_ID}" \
      --query 'StandardOutputContent' --output text)"

    if echo "$OUTPUT" | grep -q "REBOOT_REQUIRED"; then
      echo "⚠ CU installation requires a reboot to complete..."

      # Reboot the instance
      echo "Rebooting instance..."
      aws ec2 reboot-instances --region "${REGION}" --instance-ids "${INSTANCE_ID}"

      # Wait for instance to stop
      sleep 30

      # Wait for instance to be running again
      echo "Waiting for instance to come back online..."
      aws ec2 wait instance-running --region "${REGION}" --instance-ids "${INSTANCE_ID}"
      sleep 60  # Extra time for Windows to fully boot

      # Verify version after reboot
      echo "Verifying SQL Server version after reboot..."
      VERIFY_PS='
$regPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQLServer\CurrentVersion"
if (Test-Path $regPath) {
    $version = (Get-ItemProperty -Path $regPath).CurrentVersion
    Write-Host "Post-reboot version: $version"
    if ($version -eq "16.00.4195.2") {
        Write-Host "✓ CU19 version verified after reboot"
    } else {
        Write-Host "ERROR: Version is still $version after reboot"
        throw "CU19 did not apply correctly even after reboot"
    }
} else {
    throw "Cannot find SQL Server registry key"
}
'

      VERIFY_PARAMS="$(mktemp)"
      jq -Rs '{commands: [.]}' <<< "$VERIFY_PS" > "$VERIFY_PARAMS"

      VERIFY_CMD_ID="$(aws ssm send-command \
        --region "${REGION}" \
        --instance-ids "${INSTANCE_ID}" \
        --document-name "AWS-RunPowerShellScript" \
        --parameters file://"$VERIFY_PARAMS" \
        --query 'Command.CommandId' --output text)"

      # Wait for verification
      sleep 30
      VERIFY_STATUS="$(aws ssm list-command-invocations --region "${REGION}" --command-id "$VERIFY_CMD_ID" \
        --query 'CommandInvocations[0].Status' --output text 2>/dev/null || echo "Pending")"

      if [[ "$VERIFY_STATUS" != "Success" ]]; then
        echo "ERROR: Version verification failed after reboot"
        aws ssm get-command-invocation \
          --region "${REGION}" \
          --command-id "$VERIFY_CMD_ID" \
          --instance-id "${INSTANCE_ID}" \
          --query '[StandardOutputContent, StandardErrorContent]' --output text
        exit 1
      fi

      echo "✓ Version verified after reboot"
    fi

    break
  fi

  if [[ "$STATUS" == "Failed" || "$STATUS" == "Cancelled" || "$STATUS" == "TimedOut" ]]; then
    echo "Installation failed with status: $STATUS"
    aws ssm get-command-invocation \
      --region "${REGION}" \
      --command-id "$CMD_ID" \
      --instance-id "${INSTANCE_ID}" \
      --query '[StandardOutputContent, StandardErrorContent]' --output text | tail -n 200
    exit 1
  fi

  sleep 10
done

# ---------- Sysprep ----------
echo "Running Sysprep..."

SYSPREP_PS='
$ErrorActionPreference = "Stop"
$exe = Join-Path $env:ProgramFiles "Amazon\EC2Launch\ec2launch.exe"

# Ensure SQL services are stopped
try { Stop-Service SQLSERVERAGENT -Force -ErrorAction SilentlyContinue } catch {}
try { Stop-Service MSSQLSERVER   -Force -ErrorAction SilentlyContinue } catch {}
try { Stop-Service SQLBrowser    -Force -ErrorAction SilentlyContinue } catch {}

if (Test-Path $exe) {
  Write-Host "Running EC2Launch v2 sysprep..."
  & $exe sysprep --shutdown=true
} else {
  throw "EC2Launch v2 not found at $exe"
}
'

SYSPREP_PARAMS="$(mktemp)"
jq -Rs '{commands: [.]}' <<< "$SYSPREP_PS" > "$SYSPREP_PARAMS"

SYSPREP_CMD_ID="$(aws ssm send-command \
  --region "${REGION}" \
  --instance-ids "${INSTANCE_ID}" \
  --document-name "AWS-RunPowerShellScript" \
  --parameters file://"$SYSPREP_PARAMS" \
  --cloud-watch-output-config CloudWatchOutputEnabled=true \
  --query 'Command.CommandId' --output text)"

echo "Waiting for instance to stop (up to 45 minutes)..."
deadline=$((SECONDS + 2700))
while :; do
  state="$(aws ec2 describe-instances \
    --region "${REGION}" --instance-ids "${INSTANCE_ID}" \
    --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo 'unknown')"

  if [[ "$state" == "stopped" ]]; then
    echo "✓ Instance stopped"
    break
  fi

  if (( SECONDS > deadline )); then
    echo "ERROR: Instance did not stop within timeout"
    exit 1
  fi

  sleep 15
done

# ---------- Create AMI ----------
echo "Creating AMI: ${AMI_NAME}"
AMI_ID="$(aws ec2 create-image \
  --region "${REGION}" \
  --instance-id "${INSTANCE_ID}" \
  --name "${AMI_NAME}" \
  --description "WS2019 + SQL 2022 Developer CU19 (16.00.4195.2) - RDS Custom ready" \
  --output text --query ImageId)"

echo "AMI: ${AMI_ID}"
echo "Waiting for AMI to become available..."
aws ec2 wait image-available --region "${REGION}" --image-ids "${AMI_ID}"

echo ""
echo "=========================================="
echo "✓ SUCCESS! AMI created: ${AMI_ID}"
echo "=========================================="
echo ""
echo "SQL Server version: 16.00.4195.2 (CU19)"
echo ""
echo "Next: Create CEV with:"
echo "  aws rds create-custom-db-engine-version \\"
echo "    --engine custom-sqlserver-dev \\"
echo "    --engine-version 16.00.4195.2.dev-cev-$(date +%Y%m%d) \\"
echo "    --image-id ${AMI_ID} \\"
echo "    --description 'SQL Server 2022 Developer CU19' \\"
echo "    --region ${REGION}"