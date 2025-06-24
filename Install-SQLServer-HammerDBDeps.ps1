# Requires Administrator privileges to run
# This script will install MS SQL Server Developer Edition, SSMS, and ODBC Driver 18.
#
# IMPORTANT: Download URLs for Microsoft products are subject to change.
# ALWAYS VERIFY these URLs before running the script.
#
# Usage (Recommended - Use Pre-Downloaded Local SQL Server Installer):
# To automate SQL Server installation, you MUST provide the path to a local SQL Server ISO or extracted installer.
# .\Install-SQLServer-HammerDBDeps.ps1 `
#   -sqlAdminUser "YourWindowsUsername" `
#   -saPassword "YourStrongSAPassword!" `
#   -sqlInstallerLocalPath "C:\Installers\SQL2022-Developer.iso" ` # Path to your SQL Server ISO or setup.exe
#   -odbcDriverLocalPath "C:\Installers\msodbcsql.msi" `          # Optional: Local path for ODBC driver
#   -ssmsInstallerLocalPath "C:\Installers\SSMS-Setup-ENU.exe"     # Optional: Local path for SSMS

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$sqlAdminUser,

    [Parameter(Mandatory=$true)]
    [string]$saPassword,

    # --- SQL Server Developer Edition Parameters ---
    # !!! For automated installation, it is STRONGLY RECOMMENDED and often REQUIRED to provide a local path to the SQL Server ISO or extracted setup.exe.
    [string]$sqlInstallerLocalPath = "", # Set this if you have the installer locally (e.g., "C:\Installers\SQL2022-Developer.iso" or "C:\Installers\SQL2022_extracted_media\setup.exe")
    [string]$sqlInstallPath = "C:\SQLServerInstall",
    [string]$instanceName = "MSSQLSERVER", # Default instance for Developer Edition. Change if you want a named instance.

    # Default URL for SQL Server 2022 Developer online installer (used only if no local path provided, but requires manual intervention for setup)
    # This URL is primarily for reference, as automated download of full media might not be silent.
    [string]$sqlInstallerUrl = "https://go.microsoft.com/fwlink/?linkid=2215112&clcid=0x409&culture=en-us&country=US",
    [string]$sqlInstallerFileName = "SQL2022-SSEI-Dev.exe",


    # --- SSMS Parameters ---
    # Default URL for latest SSMS installer redirect link. VERIFY THIS URL.
    [string]$ssmsInstallerUrl = "https://go.microsoft.com/fwlink/?linkid=2252516",
    [string]$ssmsInstallerFileName = "SSMS-Setup-ENU.exe",
    [string]$ssmsInstallerLocalPath = "", # Set this if you have the installer locally

    # --- ODBC Driver Parameters ---
    # Default URL for ODBC Driver 18.2.1.1 for SQL Server (x64). VERIFY THIS URL.
    [string]$odbcDriverUrl = "https://download.microsoft.com/download/7/7/4/7740f17e-c045-42d4-a81d-669b939994c6/msodbcsql.msi",
    [string]$odbcDriverFileName = "msodbcsql.msi",
    [string]$odbcDriverLocalPath = "", # Set this if you have the installer locally

    # --- General Parameters ---
    [string]$downloadsDir = "C:\TempDownloads"
)

Write-Host "Starting SQL Server Developer Edition and Dependencies Installation..."

# --- Create Download Directory ---
if (-not (Test-Path $downloadsDir)) {
    New-Item -Path $downloadsDir -ItemType Directory -Force
    Write-Host "Created download directory: $downloadsDir"
}

# --- Function to handle download or use local file (for SSMS and ODBC) ---
function Get-InstallerPath {
    param (
        [string]$url,
        [string]$fileName,
        [string]$localPath,
        [string]$targetDir
    )
    $fullPath = Join-Path $targetDir $fileName
    if (-not ([string]::IsNullOrEmpty($localPath))) {
        if (Test-Path $localPath) {
            Write-Host "Using local installer: $localPath"
            return $localPath
        } else {
            Write-Warning "Local installer '$localPath' not found. Attempting to download from '$url'."
        }
    }

    Write-Host "Downloading installer from $url to $fullPath..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $fullPath -UseBasicParsing
        Write-Host "Download complete: $fullPath"
        return $fullPath
    }
    catch {
        Write-Error "Failed to download $fileName from $url. Error: $($_.Exception.Message)"
        exit 1
    }
}

# --- 1. Install SQL Server Developer Edition (Silent Installation) ---
#######commenting SQL Installation############
<# 
Write-Host "Preparing SQL Server Developer Edition installation..."

$sqlSetupExe = ""
$mountedDriveLetter = ""

# Handle local SQL Server installer path
if (-not ([string]::IsNullOrEmpty($sqlInstallerLocalPath))) {
    if (Test-Path $sqlInstallerLocalPath -PathType Leaf) { # Is it a file (e.g., .iso or .exe)?
        $extension = [System.IO.Path]::GetExtension($sqlInstallerLocalPath)
        if ($extension -eq ".iso") {
            Write-Host "Mounting SQL Server ISO: $sqlInstallerLocalPath"
            try {
                $mountResult = Mount-DiskImage -ImagePath $sqlInstallerLocalPath -PassThru
                $mountedDriveLetter = ($mountResult | Get-Volume).DriveLetter
                if (-not ([string]::IsNullOrEmpty($mountedDriveLetter))) {
                    $sqlSetupExe = Join-Path "$($mountedDriveLetter):\" "setup.exe"
                    Write-Host "ISO mounted. Setup.exe expected at: $sqlSetupExe"
                    if (-not (Test-Path $sqlSetupExe)) {
                        Write-Error "Error: setup.exe not found on mounted ISO at '$sqlSetupExe'. ISO content may be incorrect."
                        exit 1
                    }
                } else {
                    Write-Error "Failed to get drive letter for mounted ISO."
                    exit 1
                }
            }
            catch {
                Write-Error "Failed to mount ISO '$sqlInstallerLocalPath'. Error: $($_.Exception.Message)"
                exit 1
            }
        } elseif ($extension -eq ".exe") {
            Write-Host "Using local SQL Server executable: $sqlInstallerLocalPath"
            $sqlSetupExe = $sqlInstallerLocalPath
        } else {
            Write-Error "Unsupported file type for SQL Server installer local path: $extension. Expected .iso or .exe."
            exit 1
        }
    } elseif (Test-Path $sqlInstallerLocalPath -PathType Container) { # Is it a directory (extracted media)?
        Write-Host "Using local SQL Server installation directory: $sqlInstallerLocalPath"
        $sqlSetupExe = Join-Path $sqlInstallerLocalPath "setup.exe"
        if (-not (Test-Path $sqlSetupExe)) {
            Write-Error "Error: setup.exe not found in local SQL Server directory '$sqlInstallerLocalPath'."
            exit 1
        }
    } else {
        Write-Error "SQL Server installer local path '$sqlInstallerLocalPath' not found or is invalid."
        exit 1
    }
} else {
    Write-Error "ERROR: For automated SQL Server installation, you MUST provide a local path to the SQL Server Developer Edition ISO or extracted media (setup.exe) using the -sqlInstallerLocalPath parameter."
    Write-Error "The online installer does not support silent full media download or installation directly via command line."
    Write-Error "Please download the SQL Server Developer ISO manually (e.g., from your Visual Studio Subscription or Microsoft Evaluation Center) and provide its path."
    exit 1
}

# Ensure SQL Server installation path exists
if (-not (Test-Path $sqlInstallPath)) {
    New-Item -Path $sqlInstallPath -ItemType Directory -Force
}

Write-Host "Executing SQL Server Developer Edition setup. This may take a while..."

# These arguments are for setup.exe (from an ISO or extracted media)
$installLogFile = "C:\SQLDeveloperInstallLog.txt"
$sqlInstallArguments = @(
    "/ACTION=Install"
    "/quiet"
    "/IACCEPTSQLSERVERLICENSETERMS"
    "/features=SQLEngine,TOOLS" # Common features, adjust as needed
    "/instancename=$instanceName"
    "/sqlsvcaccount=`"NT Service\MSSQLSERVER`"" # Default account for default instance (MSSQLSERVER)
    "/sqlsysadminaccounts=`"$sqlAdminUser`""
    "/sapwd=`"$saPassword`""
    "/tcpenabled=1"
    "/updateenabled=false"
    "/errorreporting=false"
)

# Crucial part: Execute the determined SQL Setup executable
if (-not ([string]::IsNullOrEmpty($sqlSetupExe)) -and (Test-Path $sqlSetupExe)) {
    Write-Host "Running SQL setup: $sqlSetupExe $($sqlInstallArguments -join ' ')"
    $process = Start-Process -FilePath $sqlSetupExe -ArgumentList $sqlInstallArguments -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) {
        Write-Error "SQL Server Developer Edition installation failed with exit code $($process.ExitCode). Check $installLogFile for details."
        exit 1
    }
    Write-Host "SQL Server Developer Edition installation complete."
} else {
    Write-Error "SQL Server setup executable could not be determined or found. Aborting installation."
    exit 1
}

# --- Clean up mounted ISO if applicable ---
if (-not ([string]::IsNullOrEmpty($mountedDriveLetter))) {
    Write-Host "Dismounting SQL Server ISO..."
    try {
        Dismount-DiskImage -ImagePath $sqlInstallerLocalPath -Confirm:$false
        Write-Host "ISO dismounted."
    }
    catch {
        Write-Warning "Failed to dismount ISO '$sqlInstallerLocalPath'. Error: $($_.Exception.Message)"
    }
}
#> 
#######End of comment############

# --- 2. Install Microsoft ODBC Driver 18 for SQL Server ---
#####commenting out ODBC installation ####
<#
Write-Host "Preparing ODBC Driver 18 for SQL Server installation..."
$odbcDriverInstaller = Get-InstallerPath -url $odbcDriverUrl -fileName $odbcDriverFileName -localPath $odbcDriverLocalPath -targetDir $downloadsDir

Write-Host "Installing ODBC Driver 18 for SQL Server..."
$process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$odbcDriverInstaller`" /qn /norestart" -Wait -PassThru -NoNewWindow
if ($process.ExitCode -ne 0) {
    Write-Error "ODBC Driver 18 installation failed with exit code $($process.ExitCode)."
    exit 1
}
Write-Host "ODBC Driver 18 for SQL Server installation complete."
#>
#####End of commenting out ODBC installation ####

# --- 3. Install SQL Server Management Studio (SSMS) ---
Write-Host "Preparing SSMS installation..."
$ssmsInstaller = Get-InstallerPath -url $ssmsInstallerUrl -fileName $ssmsInstallerFileName -localPath $ssmsInstallerLocalPath -targetDir $downloadsDir

Write-Host "Installing SSMS. This may take a while..."
$process = Start-Process -FilePath $ssmsInstaller -ArgumentList "/Install /Quiet /NoRestart" -Wait -PassThru -NoNewWindow
if ($process.ExitCode -ne 0) {
    Write-Error "SSMS installation failed with exit code $($process.ExitCode)."
    exit 1
}
Write-Host "SSMS installation complete."

# --- 4. Configure SQL Server for Remote Connections ---
Write-Host "Configuring SQL Server for remote connections..."

# Initialize a flag to track module installation success
$moduleInstallFailed = $false

# Check if the 'SqlServer' PowerShell module is installed, install if not.
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Host "SqlServer PowerShell module not found. Attempting to install..."

    # Ensure NuGet provider is available (this part should be good from previous fix)
    Write-Host "Ensuring NuGet provider is installed/updated..."
    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false -ErrorAction Stop
        Write-Host "NuGet provider installed/updated successfully."
    }
    catch {
        Write-Error "CRITICAL ERROR: Failed to install or update NuGet provider. This is required for installing PowerShell modules. Error: $($_.Exception.Message)"
        $moduleInstallFailed = $true # Set flag if NuGet fails
    }

    # Attempt to install SqlServer module, but only if NuGet was successful
    if (-not $moduleInstallFailed) {
        try {
            Write-Host "Installing SqlServer PowerShell module from PSGallery..."
            Install-Module -Name SqlServer -RequiredVersion 21.1.18256 -Scope AllUsers -Force -AllowClobber -Confirm:$false -ErrorAction Stop
            Write-Host "SqlServer PowerShell module installation initiated."

            # After installation, ensure it's imported into the current session
            Write-Host "Importing SqlServer PowerShell module..."
            Import-Module SqlServer -RequiredVersion 21.1.18256 -ErrorAction Stop
            Write-Host "SqlServer PowerShell module installed and imported successfully."
        }
        catch {
            Write-Error "CRITICAL ERROR: Failed to install or import SqlServer PowerShell module. This will prevent automated TCP/IP configuration. Error: $($_.Exception.Message)"
            Write-Warning "Please try to install the 'SqlServer' module manually in an elevated PowerShell session: Install-Module -Name SqlServer -Scope AllUsers -Force -AllowClobber"
            $moduleInstallFailed = $true # Set flag if SqlServer module fails
        }
    }
} else {
    # Module is listed as available, just ensure it's imported into the current session
    Write-Host "SqlServer PowerShell module found. Ensuring it's imported..."
    try {
        Import-Module SqlServer -ErrorAction Stop
        Write-Host "SqlServer PowerShell module imported successfully."
    }
    catch {
        Write-Error "CRITICAL ERROR: Failed to import SqlServer PowerShell module, even though it's listed as available. Error: $($_.Exception.Message)"
        Write-Warning "This will prevent automated TCP/IP configuration. You might need to troubleshoot your PowerShell environment or manually import the module."
        $moduleInstallFailed = $true # Set flag if import fails
    }
}

# --- ONLY PROCEED WITH TCP/IP CONFIGURATION IF MODULE IS SUCCESSFULLY LOADED ---
if (-not $moduleInstallFailed) {
    # Ensure SQL Server Browser is running (optional but helpful for named instances)
    Set-Service -Name "SQLBrowser" -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name "SQLBrowser" -ErrorAction SilentlyContinue

    # Get SQL Server service name for the instance
    $sqlSvcName = "MSSQLSERVER" # Assuming default instance for Developer Edition
    if ($instanceName -ne "MSSQLSERVER") {
        $sqlSvcName = "MSSQL`$$instanceName"
    }

    # Double check if the service exists before attempting to configure
    if (-not (Get-Service -Name $sqlSvcName -ErrorAction SilentlyContinue)) {
        Write-Warning "SQL Server service '$sqlSvcName' not found. Manual TCP/IP configuration might be needed."
    } else {
        Write-Host "SQL Server service name: $sqlSvcName"
        try {
            $serverInstance = "localhost"
            if ($instanceName -ne "MSSQLSERVER") {
                $serverInstance += "\$instanceName"
            }

            # Check if the protocol is already enabled
            $tcpProtocol = Get-SqlProtocol -ServerInstance $serverInstance | Where-Object { $_.Name -eq "Tcp" }

            if ($null -ne $tcpProtocol) {
                if ($tcpProtocol.IsEnabled -ne $true) {
                    Write-Host "Enabling TCP/IP protocol for SQL Server instance '$serverInstance'..."
                    $tcpProtocol.IsEnabled = $true
                    $tcpProtocol.Alter()
                    Write-Host "TCP/IP protocol enabled."
                } else {
                    Write-Host "TCP/IP protocol already enabled for SQL Server instance '$serverInstance'."
                }
            } else {
                Write-Warning "TCP protocol not found for instance '$serverInstance'. Manual configuration may be required."
            }
        }
        catch {
            Write-Warning "Could not enable TCP/IP using SqlServer module. Error: $($_.Exception.Message)"
            Write-Warning "You might need to manually enable TCP/IP for '$instanceName' via SQL Server Configuration Manager (SQLServerManager16.msc or similar) or ensure SQL Server Browser is running and accessible."
        }

        # Restart SQL Server service to apply changes
        Write-Host "Restarting SQL Server service '$sqlSvcName'..."
        Restart-Service -Name $sqlSvcName -Force -ErrorAction SilentlyContinue
        Write-Host "SQL Server service restarted."
    }
} else {
    Write-Warning "Skipping SQL Server TCP/IP configuration because the SqlServer PowerShell module could not be installed/imported. Please configure manually if needed."
}

Write-Host "SQL Server Developer Edition and dependencies installation complete."
