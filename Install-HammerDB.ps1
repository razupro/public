[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    # URL for HammerDB 5.0 installer
    [string]$HammerDBInstallerUrl = "https://github.com/TPC-Council/HammerDB/releases/download/v5.0/HammerDB-5.0-Win-x64-Setup.exe",

    [Parameter(Mandatory=$false)]
    # Default download path. You can change this to a permanent location if desired.
    [string]$DownloadPath = "$env:TEMP\HammerDB-5.0-Setup.exe", 

    [Parameter(Mandatory=$false)]
    [string]$HammerDBInstallPath = "C:\Program Files\HammerDB" # Default installation path
)

Begin {
    Write-Host "Starting HammerDB Installation Script..."
    Write-Host "Attempting to install HammerDB version 5.0."
    Write-Host "HammerDB will be installed to '$HammerDBInstallPath'."
}
Process {
    # Check if HammerDB CLI executable already exists at the target path
    if (Test-Path "$HammerDBInstallPath\hammerdbcli.exe") {
        Write-Host "HammerDB appears to be already installed at '$HammerDBInstallPath'. Skipping installation."
        return
    }

    # Check if the installer file already exists locally
    if (Test-Path $DownloadPath) {
        Write-Host "HammerDB installer already exists locally at '$DownloadPath'. Skipping download."
    }
    else {
        Write-Host "Downloading HammerDB installer from '$HammerDBInstallerUrl'..."
        try {
            Invoke-WebRequest -Uri $HammerDBInstallerUrl -OutFile $DownloadPath -ErrorAction Stop
            Write-Host "Download complete: '$DownloadPath'"
        }
        catch {
            Write-Error "Failed to download HammerDB installer from GitHub. Please check the URL and your internet connection. Error: $($_.Exception.Message)"
            exit 1
        }
    }

    Write-Host "Running HammerDB installer silently using '--mode unattended' and '--prefix '$HammerDBInstallPath'..."
    try {
        $installProcess = Start-Process -FilePath $DownloadPath -ArgumentList "--mode unattended", "--prefix `"$HammerDBInstallPath`"" -Wait -PassThru -ErrorAction Stop
        if ($installProcess.ExitCode -eq 0) {
            Write-Host "HammerDB installed successfully to '$HammerDBInstallPath'."
        }
        else {
            Write-Error "HammerDB installation failed with exit code $($installProcess.ExitCode). This often indicates an issue during the unattended install."
            Write-Warning "Please try running '$DownloadPath --help' in a command prompt for more options, or perform a manual installation."
            exit 1
        }
    }
    catch {
        Write-Error "Failed to execute HammerDB installer. Ensure you are running PowerShell as Administrator. Error: $($_.Exception.Message)"
        exit 1
    }
}
End {
    Write-Host "HammerDB Installation Script Finished."
}
