@echo off
setlocal

REM ==== Input Parameters ====
if "%~7"=="" (
    echo Usage: run_tpcc_benchmark.bat ^<SQL_SERVER^> ^<SQL_USER^> ^<SQL_PASSWORD^> ^<WAREHOUSES^> ^<DURATION^> ^<VUS_CSV^> ^<HAMMERDB_PATH^>
    echo Example: run_tpcc_benchmark.bat 10.128.5.15 sa MyPass123 10 5 "10,20,30,40" "C:\Program Files\HammerDB-5.0"
    exit /b 1
)

set SQL_SERVER=%1
set SQL_USER=%2
set SQL_PASSWORD=%3
set WAREHOUSES=%4
set DURATION=%5
set VUS_CSV=%6
set HAMMERDB_PATH=%7

REM ==== SQL Cleanup ====
echo 🔧 Running SQL Cleanup...
powershell -ExecutionPolicy Bypass -File cleanup_sql.ps1 -Server %SQL_SERVER% -Username %SQL_USER% -Password %SQL_PASSWORD%
IF %ERRORLEVEL% NEQ 0 (
    echo ❌ SQL Cleanup failed. Exiting.
    exit /b %ERRORLEVEL%
)

REM ==== Generate TCL Script ====
echo 🛠️ Generating TCL Benchmark Script...

copy mssql_tpcc_benchmark.template.tcl mssql_tpcc_benchmark.tcl >nul

powershell -Command "(Get-Content mssql_tpcc_benchmark.tcl) `
    -replace '{DBSERVER}', '%SQL_SERVER%' `
    -replace '{DBUSER}', '%SQL_USER%' `
    -replace '{DBPASSWORD}', '%SQL_PASSWORD%' `
    -replace '{WAREHOUSES}', '%WAREHOUSES%' `
    -replace '{DURATION}', '%DURATION%' `
    -replace '{VUS}', '%VUS_CSV%' `
    | Set-Content mssql_tpcc_benchmark.tcl"

REM ==== Run HammerDB ====
echo 🚀 Running HammerDB Benchmark...
cd /d %HAMMERDB_PATH%
hammerdbcli.exe tcl auto %~dp0%mssql_tpcc_benchmark.tcl

echo ===============================================
echo ✅ Benchmark completed successfully.
echo ===============================================
pause
