# ===================================
# HammerDB MSSQL TPC-C TCL Benchmark Template (Supports HammerDB 5.0 'args')
# ===================================

# ========================
# Default Parameters
# ========================
set dbserver "localhost"
set dbuser "sa"
set dbpassword "YourPassword"
set dbname "tpcc"
set warehouses 5
set rampup 2
set duration 5
set workload_vusers {10 20 30 40}

# ========================
# Parse args
# ========================
foreach {key val} $args {
    if {$key eq "warehouses"} {set warehouses $val}
    if {$key eq "rampup"} {set rampup $val}
    if {$key eq "duration"} {set duration $val}
    if {$key eq "vusers"} {
        set workload_vusers [split $val ","]
    }
    if {$key eq "dbserver"} {set dbserver $val}
    if {$key eq "dbuser"} {set dbuser $val}
    if {$key eq "dbpassword"} {set dbpassword $val}
}

# ========================
# Display Configuration
# ========================
puts "======== Benchmark Parameters ========"
puts "Database Server   : $dbserver"
puts "Database User     : $dbuser"
puts "Database Password : (hidden)"
puts "Database Name     : $dbname"
puts "Warehouses        : $warehouses"
puts "Ramp-up (minutes) : $rampup"
puts "Duration (minutes): $duration"
puts "Virtual Users     : $workload_vusers"
puts "======================================="


# ========================
# Database Cleanup
# ========================
puts "[INFO] Connecting to SQL Server for cleanup..."
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


# ========================
# Schema Build
# ========================
puts "[INFO] Starting schema build..."

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


# ========================
# Run Workloads
# ========================
foreach vuser $workload_vusers {
    puts "[INFO] Starting workload with $vuser Virtual Users..."

    vuset logtotemp 1
    vuset vu $vuser
    loadscript

    vucreate

    puts "[INFO] Running workload..."
    vurun
    waittocomplete

    puts "[INFO] Workload with $vuser VUs completed."
}

puts "[INFO] All workloads completed."

exit
