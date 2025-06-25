param (
    [string]$Server,
    [string]$Username,
    [string]$Password
)

try {
    Write-Host "🔧 Connecting to SQL Server $Server for cleanup..."

    $SqlQuery = Get-Content ".\cleanup.sql" -Raw

    Invoke-Sqlcmd -ServerInstance $Server -Username $Username -Password $Password -Query $SqlQuery

    Write-Host "✅ SQL Cleanup completed."
}
catch {
    Write-Error "❌ SQL Cleanup failed: $_"
    exit 1
}
