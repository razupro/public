# HammerDB MSSQL TPC-C Benchmark Template with Command Line Parameters

# ===============================
# Read Command Line Parameters
# ===============================

# Default values
set dbserver "10.128.5.15"
set dbuser "sa"
set dbpassword "YourPassword"
set dbinstance "MSSQLSERVER"
set dbname "tpcc"

# Defaults for parameters
set warehouses 5
set rampup 2
set duration 5
set workload_vusers {10 20 30 40}

# Parse arguments
foreach arg $argv {
    if {[regexp {warehouses=(.+)} $arg -> val]} {set warehouses $val}
    if {[regexp {rampup=(.+)} $arg -> val]} {set rampup $val}
    if {[regexp {duration=(.+)} $arg -> val]} {set duration $val}
    if {[regexp {vusers=(.+)} $arg -> val]} {
        set workload_vusers [split $val ","]
    }
}

puts "======== Benchmark Parameters ========"
puts "Database Server   : $dbserver"
puts "Database User     : $dbuser"
puts "Database Password : (hidden)"
puts "Database Name     : $dbname"
puts "Warehouses        : $warehouses"
puts "Ramp-up (minutes) : $rampup"
puts "Duration (minutes): $duration"
puts "Virtual Users     : $workload_vusers"
puts "========================================"

# ===============================
# Database Cleanup
# ===============================

puts "\n[INFO] Connecting to SQL Server for cleanup..."
dbset db mssqls
diset connection mssqls_server $dbserver
diset connection mssqls_user $dbuser
diset connection mssqls_password $dbpassword
diset connection mssqls_dbase master

puts "[INFO] Dropping existing database '$dbname' if exists..."
mssqls_exec "IF DB_ID('$dbname') IS NOT NULL BEGIN ALTER DATABASE [$dbname] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$dbname]; END"

puts "[INFO] Dropping user 'tpcc' if exists..."
mssqls_exec "IF EXISTS (SELECT * FROM sys.sql_logins WHERE name = 'tpcc') BEGIN DROP LOGIN [tpcc]; END"

puts "[INFO] Cleanup completed."

# ===============================
# Schema Build
# ===============================

puts "\n[INFO] Starting schema build..."

diset tpcc mssqls_server $dbserver
diset tpcc mssqls_user $dbuser
diset tpcc mssqls_password $dbpassword
diset tpcc mssqls_dbase $dbname
diset tpcc mssqls_authentication sqlserver
diset tpcc count_ware $warehouses
diset tpcc total_iterations 1
diset tpcc tpcc_vu 1
diset tpcc mssqls_driver odbc

buildschema
waittocomplete

puts "[INFO] Schema build completed."

# ===============================
# Run Workloads
# ===============================

foreach vuser $workload_vusers {
    puts "\n[INFO] Starting workload with $vuser Virtual Users..."

    # Configure
    vuset logtotemp 1
    vuset vu $vuser
    loadscript

    # Run
    vucreate

    puts "[INFO] Running workload..."
    vurun
    waittocomplete

    puts "[INFO] Workload with $vuser VUs completed."
}

puts "\n[INFO] All workloads completed."

exit
