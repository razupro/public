# TestScript.ps1 - For troubleshooting 'Begin' error
[CmdletBinding()]
param(
    [string]$TestMessage = "Hello from Process block!"
)

Begin {
    Write-Host "--- Starting Begin block ---"
    Write-Host "This runs once at the start."
}

Process {
    Write-Host "--- Running Process block ---"
    Write-Host "Message: $TestMessage"
    Write-Host "This runs for each pipeline input (or once if no input)."
}

End {
    Write-Host "--- Finishing End block ---"
    Write-Host "This runs once at the end."
}
