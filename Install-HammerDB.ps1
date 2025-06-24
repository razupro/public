[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    # Updated URL to HammerDB's GitHub Releases for version 5.0
    [string]$HammerDBInstallerUrl = "https://github.com/TPC-Council/HammerDB/releases/download/v5.0/HammerDB-5.0-Win-x64-Setup.exe",

    [Parameter(Mandatory=$false)]
    [string]$DownloadPath = "$env:TEMP\HammerDB-5.0-Setup.exe", # Changed default filename and extension to .exe

    [Parameter(Mandatory=$false)]
    [string]$HammerDBInstallPath = "C:\Program Files\HammerDB" # Default installation path for HammerDB
)

Begin {
    Write-Host "Starting HammerDB Installation Script..."
    Write-Host "Attempting to install HammerDB version 5.0 from GitHub."
}
Process {
    # Check if HammerDB CLI executable already exists
    if (Test-Path "$HammerDBInstallPath\hammerdbcli.exe") {
        Write-Host "HammerDB appears to be already installed at '$HammerDBInstallPath'. Skipping installation."
        return
    }

    Write-Host "Downloading HammerDB installer from '$HammerDBInstallerUrl'..."
    try {
        Invoke-WebRequest -Uri $HammerDBInstallerUrl -OutFile $DownloadPath -ErrorAction Stop
        Write-Host "Download complete: '$DownloadPath'"
    }
    catch {
        Write-Error "Failed to download HammerDB installer from GitHub. Please check the URL and your internet connection. Error: $($_.Exception.Message)"
        exit 1
    }

    Write-Host "Running HammerDB installer silently..."
    try {
        # Executing the .exe installer with a silent switch (/S).
        # This is a common switch for many installers (e.g., Inno Setup, NSIS).
        # If this fails, you might need to run "$DownloadPath /?" manually to find the correct silent switch.
        $installProcess = Start-Process -FilePath $DownloadPath -ArgumentList "/S" -Wait -PassThru -ErrorAction Stop
        if ($installProcess.ExitCode -eq 0) {
            Write-Host "HammerDB installed successfully to '$HammerDBInstallPath'."
        }
        else {
            Write-Error "HammerDB installation failed with exit code $($installProcess.ExitCode). This often means the silent install switch was incorrect or there's another issue."
            Write-Warning "Consider running '$DownloadPath /?' in a command prompt to see available silent install options, then manually run the installer if needed."
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
