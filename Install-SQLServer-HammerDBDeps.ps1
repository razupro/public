# Requires Administrator privileges to run
# This script will install MS SQL Server Developer Edition, SSMS, and ODBC Driver 18.
#
# IMPORTANT: Download URLs for Microsoft products are subject to change.
# ALWAYS VERIFY these URLs before running the script.
#
# Usage (Download from Internet - Default):
# .\Install-SQLServer-HammerDBDeps.ps1 -sqlAdminUser "YourWindowsUsername" -saPassword "YourStrongSAPassword!"
#
# Or (Use Pre-Downloaded Local Installers):
# .\Install-SQLServer-HammerDBDeps.ps1 `
#   -sqlAdminUser "YourWindowsUsername" `
#   -saPassword "YourStrongSAPassword!" `
#   -sqlInstallerLocalPath "C:\Installers\SQL2022-SSEI-Dev.exe" `
#   -odbcDriverLocalPath "C:\Installers\msodbcsql.msi" `
#   -ssmsInstallerLocalPath "C:\Installers\SSMS-Setup-ENU.exe"

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$sqlAdminUser,

    [Parameter(Mandatory=$true)]
    [string]$saPassword,

    # --- SQL Server Developer Edition Parameters ---
    # Default URL for SQL Server 2022 Developer online installer. VERIFY THIS URL.
    [string]$sqlInstallerUrl = "https://go.microsoft.com/fwlink/?linkid=2215112&clcid=0x409&culture=en-us&country=US",
    [string]$sqlInstallerFileName = "SQL2022-SSEI-Dev.exe",
    [string]$sqlInstallerLocalPath = "", # Set this if you have the installer locally (e.g., "C:\Installers\SQL2022-SSEI-Dev.exe")
    [string]$sqlInstallPath = "C:\SQLServerInstall",
    [string]$instanceName = "MSSQLSERVER", # Default instance for Developer Edition. Change if you want a named instance.

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

# --- Function to handle download or use local file ---
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
Write-Host "Preparing SQL Server Developer Edition installation..."
$sqlInstaller = Get-InstallerPath -url $sqlInstallerUrl -fileName $sqlInstallerFileName -localPath $sqlInstallerLocalPath -targetDir $downloadsDir

if (-not (Test-Path $sqlInstallPath)) {
    New-Item -Path $sqlInstallPath -ItemType Directory -Force
}

Write-Host "Executing SQL Server Developer Edition setup. This may take a while..."

# For the online installer (e.g., SQL2022-SSEI-Dev.exe), it first downloads components.
# This approach starts the online installer silently to perform the full installation.
# If you are using a full ISO/extracted installer, you'd typically run setup.exe from the extracted path.
$installLogFile = "C:\SQLDeveloperInstallLog.txt"
$sqlInstallArguments = @(
    "/install"
    "/quiet"
    "/accepteulaterms"
    "/features=SQLEngine,SSMS,TOOLS,ADVANCEDANALYTICS,FULLTEXT,SQL_INST_MP,DBREPLICATION,IS,DQ,AS" # Common features, adjust as needed
    "/instancename=$instanceName"
    "/sqlsvcaccount=`"NT Service\MSSQLSERVER`"" # Default account for default instance (MSSQLSERVER)
    "/sqlsysadminaccounts=`"$sqlAdminUser`""
    "/sapwd=`"$saPassword`""
    "/tcpenabled=1"
    "/browsersvcupdatetype=Automatic" # Changed from STARTUPTYPE for some versions
    "/updateenabled=false"
    "/errorreporting=false"
    "/sqletlogdirectory=$sqlInstallPath"
    "/installsharedir=`"C:\Program Files\Microsoft SQL Server\`""
    "/installsharedwowdir=`"C:\Program Files (x86)\Microsoft SQL Server\`""
    "/logfile=$installLogFile"
)

Write-Host "Running online installer: $sqlInstaller $($sqlInstallArguments -join ' ')"
$process = Start-Process -FilePath $sqlInstaller -ArgumentList $sqlInstallArguments -Wait -PassThru -NoNewWindow
if ($process.ExitCode -ne 0) {
    Write-Error "SQL Server Developer Edition installation failed with exit code $($process.ExitCode). Check $installLogFile for details."
    exit 1
}
Write-Host "SQL Server Developer Edition installation complete."

# --- 2. Install Microsoft ODBC Driver 18 for SQL Server ---
Write-Host "Preparing ODBC Driver 18 for SQL Server installation..."
$odbcDriverInstaller = Get-InstallerPath -url $odbcDriverUrl -fileName $odbcDriverFileName -localPath $odbcDriverLocalPath -targetDir $downloadsDir

Write-Host "Installing ODBC Driver 18 for SQL Server..."
$process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$odbcDriverInstaller`" /qn /norestart" -Wait -PassThru -NoNewWindow
if ($process.ExitCode -ne 0) {
    Write-Error "ODBC Driver 18 installation failed with exit code $($process.ExitCode)."
    exit 1
}
Write-Host "ODBC Driver 18 for SQL Server installation complete."

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
# Check if the 'SqlServer' PowerShell module is installed, install if not.
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Host "SqlServer PowerShell module not found. Installing..."
    Install-Module -Name SqlServer -Scope AllUsers -Force -AllowClobber -Confirm:$false
    Import-Module SqlServer
    Write-Host "SqlServer PowerShell module installed."
} else {
    Import-Module SqlServer
}

# Ensure SQL Server Browser is running (optional but helpful for named instances)
Set-Service -Name "SQLBrowser" -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service -Name "SQLBrowser" -ErrorAction SilentlyContinue

# Get SQL Server service name for the instance
# For default instance (MSSQLSERVER), service name is MSSQLSERVER.
# For named instance, it would be MSSQL$INSTANCENAME
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
        # Use SQL Management Objects (SMO) to enable TCP/IP.
        # This requires the SqlServer module and connectivity to the instance.
        # It's more reliable than direct WMI calls for this specific task when SMO is available.
        $serverInstance = "localhost" # Assuming script runs on the same machine as SQL Server
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

Write-Host "SQL Server Developer Edition and dependencies installation complete."