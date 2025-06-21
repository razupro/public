# Requires Administrator privileges to run

Write-Host "Starting Windows VM Setup..."

# --- 1. Enable OpenSSH Server ---
Write-Host "Checking OpenSSH Server status..."
$sshServer = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Server*' }

if ($sshServer.State -eq 'NotPresent') {
    Write-Host "OpenSSH Server not found. Installing..."
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to install OpenSSH Server."
        exit 1
    }
    Write-Host "OpenSSH Server installed."
} else {
    Write-Host "OpenSSH Server already installed."
}

# --- 2. Configure OpenSSH Service ---
Write-Host "Configuring OpenSSH SSH Server service..."
Set-Service -Name sshd -StartupType Automatic
Start-Service -Name sshd

# Optional: Ensure PasswordAuthentication is enabled in sshd_config
$sshdConfigPath = "$Env:ProgramData\ssh\sshd_config"
if (-not (Test-Path $sshdConfigPath)) {
    # If the file doesn't exist, it might be the first run, or a fresh install.
    # OpenSSH will create a default one. We'll create a basic one if not found.
    New-Item -Path $sshdConfigPath -ItemType File -Force
    Add-Content -Path $sshdConfigPath -Value @"
# This is a basic sshd_config. Modify as needed.
Port 22
ListenAddress 0.0.0.0
PasswordAuthentication yes
Subsystem powershell C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -sshs -NoLogo
"@
} else {
    # Ensure PasswordAuthentication is set to yes
    (Get-Content $sshdConfigPath) | ForEach-Object {
        if ($_ -match '^\s*#?\s*PasswordAuthentication\s+(.*)$') {
            "PasswordAuthentication yes"
        } elseif ($_ -match '^\s*#?\s*Subsystem\s+powershell\s+(.*)$') {
            "Subsystem powershell C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -sshs -NoLogo"
        } else {
            $_
        }
    } | Set-Content $sshdConfigPath
}

Restart-Service sshd
Write-Host "OpenSSH SSH Server service configured and restarted."

# --- 3. Configure Windows Firewall ---
Write-Host "Configuring Windows Firewall for SSH (Port 22) and SQL Server (Port 1433)..."

# Allow SSH (Port 22)
$ruleNameSSH = "SSH Access (Port 22)"
if (-not (Get-NetFirewallRule -DisplayName $ruleNameSSH -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $ruleNameSSH -Direction Inbound -Action Allow -Protocol TCP -LocalPort 22
    Write-Host "Firewall rule '$ruleNameSSH' created."
} else {
    Write-Host "Firewall rule '$ruleNameSSH' already exists."
}

# Allow SQL Server (Port 1433)
$ruleNameSQL = "SQL Server Access (Port 1433)"
if (-not (Get-NetFirewallRule -DisplayName $ruleNameSQL -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $ruleNameSQL -Direction Inbound -Action Allow -Protocol TCP -LocalPort 1433
    Write-Host "Firewall rule '$ruleNameSQL' created."
} else {
    Write-Host "Firewall rule '$ruleNameSQL' already exists."
}

# Optional: Enable Remote Desktop (already often enabled by default)
$ruleNameRDP = "Remote Desktop (TCP-In)"
if (-not (Get-NetFirewallRule -DisplayName $ruleNameRDP -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $ruleNameRDP -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3389
    Write-Host "Firewall rule '$ruleNameRDP' created."
} else {
    Write-Host "Firewall rule '$ruleNameRDP' already exists."
}


Write-Host "Windows VM Setup complete. You should now be able to SSH to this VM."
Write-Host "Example SSH command: ssh UserName@YourVM_IPAddress"