# Create a directory for your scripts if it doesn't exist
New-Item -ItemType Directory -Path "C:\Scripts\HammerDB" -Force | Out-Null

# Define the full script content using a here-string
$scriptContent = @"
[CmdletBinding(SupportsShouldProcess=`$true)]
param(
    [Parameter(Mandatory=`$true, HelpMessage="SQL Server instance name (e.g., 'localhost' or 'localhost\\SQLEXPRESS').")]
    [string]`$InstanceName, 

    [Parameter(Mandatory=`$true, HelpMessage="SQL Server 'sa' account password. Used for initial setup and user creation.")]
    [string]`$SaPassword, 

    [Parameter(Mandatory=`$false, HelpMessage="Name of the TPC-C database to create.")]
    [string]`$DbName = "TPCC_HammerDB",

    [Parameter(Mandatory=`$false, HelpMessage="Dedicated SQL Server login/user for HammerDB.")]
    [string]`$HammerDBUser = "hammerdb_user",

    [Parameter(Mandatory=`$false, HelpMessage="Password for the dedicated HammerDB user. MUST be strong.")]
    [string]`$HammerDBUserPassword = "HammerDB_User_Password123!", # IMPORTANT: Use a strong, unique password!

    [Parameter(Mandatory=`$true, HelpMessage="Number of TPC-C warehouses for schema build and benchmark.")]
    [int]`$Warehouses, 

    [Parameter(Mandatory=`$false, HelpMessage="Duration of each benchmark run in seconds.")]
    [int]`$RunTimeSeconds = 300, # Default 5 minutes

    [Parameter(Mandatory=`$false, HelpMessage="Ramp-up time for each benchmark run in seconds.")]
    [int]`$RampUpSeconds = 60, # Default 1 minute

    [Parameter(Mandatory=`$true, HelpMessage="An array of Virtual Users (VUs) to test, e.g., @(10,20,30,40).")]
    [int[]]`$VirtualUsers 
)

# --- Configuration ---
`$HammerDBCLIPath = "C:\Program Files\HammerDB\hammerdbcli.exe" # Default HammerDB CLI path
`$TCLScriptsDir = Join-Path `$PSScriptRoot "HammerDB_TCL_Scripts"
`$ResultsDir = Join-Path `$PSScriptRoot "HammerDB_Benchmark_Results"

# --- Functions ---

function Test-SQLConnection {
    param(`$ServerName, `$UserName, `$Password)
    try {
        `$conn = New-Object System.Data.SqlClient.SqlConnection
        `$conn.ConnectionString = "Server=`$ServerName;User ID=`$UserName;Password=`$Password;Connection Timeout=5;"
        `$conn.Open()
        `$conn.Close()
        return `$true
    } catch {
        Write-Warning "SQL Connection Test Failed to '`$ServerName' for user '`$UserName'. Error: `$(_.Exception.Message)"
        return `$false
    }
}

function Invoke-SQLCMDCommand {
    param(
        [Parameter(Mandatory=`$true)]
        [string]`$ServerInstance,
        [Parameter(Mandatory=`$true)]
        [string]`$UserName,
        [Parameter(Mandatory=`$true)]
        [string]`$Password,
        [Parameter(Mandatory=`$true)]
        [string]`$Query
    )
    `$sqlcmdPath = "sqlcmd.exe"
    # Ensure sqlcmd.exe is in PATH or specify full path (e.g., "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe")
    if (-not (Get-Command `$sqlcmdPath -ErrorAction SilentlyContinue)) {
        Write-Error "sqlcmd.exe not found. Please ensure SQL Server Client Tools are installed and sqlcmd.exe is in your system PATH."
        exit 1
    }

    `$arguments = "-S `"`$ServerInstance`"`" -U `"`$UserName`"`" -P `"`$Password`"`" -Q `"`$Query`"`""
    
    Write-Verbose "Executing SQLCMD: `$sqlcmdPath `$arguments"
    try {
        `$process = Start-Process -FilePath `$sqlcmdPath -ArgumentList `$arguments -NoNewWindow -Wait -PassThru -ErrorAction Stop
        if (`$process.ExitCode -ne 0) {
            `$errorOutput = `$process | Select-Object -ExpandProperty StandardError | Out-String # Attempt to capture stderr
            Write-Error "SQLCMD command failed with exit code `$(`$process.ExitCode). Query: '`$Query'. Error: `$(`$errorOutput)"
            exit 1
        }
    }
    catch {
        Write-Error "Error executing SQLCMD. Query: '`$Query'. Error: `$(_.Exception.Message)"
        exit 1
    }
}

function Generate-TCLScript {
    param(
        [Parameter(Mandatory=`$true)]
        [string]`$FileName,
        [Parameter(Mandatory=`$true)]
        [string]`$ScriptContent
    )
    try {
        New-Item -ItemType Directory -Path `$TCLScriptsDir -Force | Out-Null
        `$filePath = Join-Path `$TCLScriptsDir `$FileName
        `$ScriptContent | Out-File `$filePath -Encoding ASCII -Force
        Write-Host "Generated TCL script: '`$filePath'"
        return `$filePath
    }
    catch {
        Write-Error "Failed to generate TCL script '`$FileName'. Error: `$(_.Exception.Message)"
        exit 1
    }
}

# --- Main Script Logic ---
Begin {
    Write-Host "Starting HammerDB TPC-C Benchmark Script..."

    # Check for HammerDB CLI presence
    if (-not (Test-Path `$HammerDBCLIPath)) {
        Write-Error "HammerDB CLI not found at '`$HammerDBCLIPath'. Please ensure HammerDB is installed via 'Install-HammerDB.ps1'."
        exit 1
    }

    # Test initial SQL Server connection with 'sa'
    Write-Host "Testing SQL Server connection to '`$InstanceName' with 'sa' user..."
    if (-not (Test-SQLConnection -ServerName `$InstanceName -UserName "sa" -Password `$SaPassword)) {
        Write-Error "Failed to connect to SQL Server '`$InstanceName' with 'sa' user. Please ensure SQL Server is running and SQL Server Authentication is enabled for 'sa' with the correct password."
        exit 1
    }
    Write-Host "SQL Server connection successful."

    # Create output directories
    New-Item -ItemType Directory -Path `$TCLScriptsDir -Force | Out-Null
    New-Item -ItemType Directory -Path `$ResultsDir -Force | Out-Null
}
Process {
    # --- 1. Drop Database if it exists ---
    if (`$PSCmdlet.ShouldProcess("Drop database '`$DbName'", "Are you sure you want to drop the existing database?")) {
        Write-Host "Dropping existing database '`$DbName' if it exists..."
        try {
            Invoke-SQLCMDCommand -ServerInstance `$InstanceName -UserName "sa" -Password `$SaPassword `
                -Query "ALTER DATABASE [`$DbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; IF DB_ID('`$DbName') IS NOT NULL DROP DATABASE [`$DbName];"
            Write-Host "Database '`$DbName' dropped (if it existed)."
        }
        catch {
            Write-Error "Error dropping database: `$(_.Exception.Message)"
            exit 1
        }
    }

    # --- 2. Drop user and login if they exist ---
    if (`$PSCmdlet.ShouldProcess("Drop SQL login and user '`$HammerDBUser'", "Are you sure you want to drop the existing HammerDB login and user?")) {
        Write-Host "Dropping existing user '`$HammerDBUser' and login if they exist..."
        try {
            # Switch to master for login drop, then drop user in target DB if it exists
            Invoke-SQLCMDCommand -ServerInstance `$InstanceName -UserName "sa" -Password `$SaPassword `
                -Query "USE [master]; IF EXISTS (SELECT * FROM sys.sql_logins WHERE name = N'`$HammerDBUser') DROP LOGIN [`$HammerDBUser];"
            Invoke-SQLCMDCommand -ServerInstance `$InstanceName -UserName "sa" -Password `$SaPassword `
                -Query "USE [`$DbName]; IF EXISTS (SELECT * FROM sys.database_principals WHERE name = N'`$HammerDBUser') DROP USER [`$HammerDBUser];"
            Write-Host "User '`$HammerDBUser' and login dropped (if they existed)."
        }
        catch {
            Write-Error "Error dropping user/login: `$(_.Exception.Message)"
            exit 1
        }
    }

    # --- Create new database and HammerDB user ---
    Write-Host "Creating database '`$DbName' and login/user '`$HammerDBUser'..."
    try {
        # Create database with compatibility level 160 (SQL Server 2022) and Full Recovery
        Invoke-SQLCMDCommand -ServerInstance `$InstanceName -UserName "sa" -Password `$SaPassword `
            -Query "CREATE DATABASE [`$DbName]; ALTER DATABASE [`$DbName] SET RECOVERY FULL; ALTER DATABASE [`$DbName] SET COMPATIBILITY_LEVEL = 160;" 
        
        # NOTE: Initial file sizing below is an estimation. For large W, consider larger initial sizes.
        # This part assumes default data/log paths for SQL 2022 default instance.
        # It's more robust to let SQL Server autogrow unless specific performance tuning is needed.
        # If your SQL data root is different or you have a named instance, these paths need adjustment.
        # This section is commented out for simplicity, as autogrowth handles initial sizing well for most TPC-C
        # # Get SQL Server data root path dynamically (for default instance)
        # `$sqlDataRoot = (Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQLServer\Parameters -Name SQLDataRoot).SqlDataRoot
        # `$dataFilePath = Join-Path `$sqlDataRoot "Data\`$DbName.mdf"
        # `$logFilePath = Join-Path `$sqlDataRoot "Log\`$DbName_log.ldf"
        # Invoke-SQLCMDCommand -ServerInstance `$InstanceName -UserName "sa" -Password `$SaPassword `
        #     -Query "ALTER DATABASE [`$DbName] MODIFY FILE (NAME = N'`$DbName', SIZE = `$(`$Warehouses * 10)MB, FILEGROWTH = 1GB );" # Data file initial size
        # Invoke-SQLCMDCommand -ServerInstance `$InstanceName -UserName "sa" -Password `$SaPassword `
        #     -Query "ALTER DATABASE [`$DbName] MODIFY FILE (NAME = N'`$DbName_log', SIZE = `$(`$Warehouses * 2)MB, FILEGROWTH = 256MB );" # Log file initial size
        
        # Create SQL Login and User for HammerDB
        Invoke-SQLCMDCommand -ServerInstance `$InstanceName -UserName "sa" -Password `$SaPassword `
            -Query "CREATE LOGIN [`$HammerDBUser] WITH PASSWORD = N'`$HammerDBUserPassword', CHECK_POLICY = OFF; USE [`$DbName]; CREATE USER [`$HammerDBUser] FOR LOGIN [`$HammerDBUser]; ALTER ROLE [db_owner] ADD MEMBER [`$HammerDBUser];"
        
        Write-Host "Database '`$DbName' and user '`$HammerDBUser' created successfully."
    }
    catch {
        Write-Error "Error creating database or user: `$(_.Exception.Message)"
        exit 1
    }

    # --- Generate TCL script for Schema Build ---
    Write-Host "Generating TCL script for schema build for `$Warehouses warehouses..."
    `$schemaBuildTCL = @"
# Connect to SQL Server
dbset db sqlserver
dbset server `$InstanceName
dbset inst `$InstanceName
dbset user `$HammerDBUser
dbset password `$HammerDBUserPassword
dbset tpcc
dbset tpcc_driver tcl
dbset tpcc_warehouses `$Warehouses

# Build Schema
vuser auto
vu 1 ; # Only 1 virtual user is needed for schema build
buildschema
wait for buildschema complete
disconnect
quit
"@
    `$schemaTCLFile = Generate-TCLScript "build_schema_`$Warehouses`W.tcl" `$schemaBuildTCL

    Write-Host "Running schema build for `$Warehouses warehouses (this may take some time)..."
    try {
        `$buildProcess = Start-Process -FilePath `$HammerDBCLIPath -ArgumentList "-f `"`$schemaTCLFile`"" -NoNewWindow -Wait -PassThru -ErrorAction Stop
        if (`$buildProcess.ExitCode -eq 0) {
            Write-Host "Schema build complete for `$Warehouses warehouses."
        } else {
            Write-Error "Schema build failed with exit code `$(`$buildProcess.ExitCode). Please review HammerDB logs if any."
            exit 1
        }
    }
    catch {
        Write-Error "Error running HammerDB CLI for schema build: `$(_.Exception.Message)"
        exit 1
    }

    # --- Run Workload with Different Virtual Users ---
    Write-Host "Starting TPC-C benchmark for different Virtual Users: `$(`$VirtualUsers -join ', ')..."

    foreach (`$vuCount in `$VirtualUsers | Sort-Object) { # Ensure VUs are run in ascending order
        Write-Host "--- Running benchmark with `$vuCount Virtual Users ---"
        
        # Generate TCL script for Benchmark Run
        `$benchmarkRunTCL = @"
# Connect to SQL Server
dbset db sqlserver
dbset server `$InstanceName
dbset inst `$InstanceName
dbset user `$HammerDBUser
dbset password `$HammerDBUserPassword
dbset tpcc
dbset tpcc_driver tcl
dbset tpcc_warehouses `$Warehouses

# Benchmark run
vuser auto
vuser `$vuCount
load tpc-c
timer `$RunTimeSeconds
rampup `$RampUpSeconds
print vu metrics
disconn
log off
quit
"@
        `$benchmarkTCLFile = Generate-TCLScript "run_benchmark_`$Warehouses`W_`$vuCount`VU.tcl" `$benchmarkRunTCL
        `$resultsFile = Join-Path `$ResultsDir "TPCC_Results_`$Warehouses`W_`$vuCount`VU_`$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

        Write-Host "Executing benchmark for `$vuCount VUs. Results will be saved to: '`$resultsFile'"
        try {
            # Redirect StandardOutput to a file to capture HammerDB's console output (metrics)
            `$benchmarkProcess = Start-Process -FilePath `$HammerDBCLIPath -ArgumentList "-f `"`$benchmarkTCLFile`"" -NoNewWindow -Wait -PassThru -RedirectStandardOutput `$resultsFile -ErrorAction Stop
            if (`$benchmarkProcess.ExitCode -eq 0) {
                Write-Host "Benchmark for `$vuCount VUs completed successfully. Results saved to '`$resultsFile'."
                Get-Content `$resultsFile | Select-String -Pattern "TPC-C Transactions" # Display key metrics in console
            } else {
                Write-Warning "Benchmark for `$vuCount VUs failed with exit code `$(`$benchmarkProcess.ExitCode). Check '`$resultsFile' for full details."
            }
        }
        catch {
            Write-Error "Error running HammerDB CLI for benchmark: `$(_.Exception.Message)"
        }
        Write-Host "--- Benchmark for `$vuCount Virtual Users Finished ---`n"
    }
}
End {
    Write-Host "HammerDB TPC-C Benchmark Script Finished."
    Write-Host "All generated TCL scripts are in '`$TCLScriptsDir'"
    Write-Host "All benchmark results are in '`$ResultsDir'"
}
"@ | Set-Content -Path "C:\Scripts\HammerDB\Run-HammerDB_TPCC_Benchmark.ps1" -Encoding UTF8

Write-Host "Run-HammerDB_TPCC_Benchmark.ps1 has been created/overwritten at C:\Scripts\HammerDB\Run-HammerDB_TPCC_Benchmark.ps1"
Write-Host "You can now run it using: C:\Scripts\HammerDB\Run-HammerDB_TPCC_Benchmark.ps1 -InstanceName \"localhost\" -SaPassword \"YourPassword\" -Warehouses 8 -VirtualUsers @(1,2)"
