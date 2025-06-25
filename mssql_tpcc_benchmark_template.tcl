# ===================================================
# HammerDB 5.0 TCL Benchmark Script - SQL Server TPC-C
# Fully automated workload with multiple virtual users
# ===================================================

# ---- Configuration ----
set dbserver "10.128.5.15"
set dbuser "sa"
set dbpassword "YourPassword"
set dbname "tpcc"

set warehouses 5
set workload_vusers {10 20 30 40}
set rampup 2    ;# Informational only
set duration 5  ;# Informational only

# ---- Display Configuration ----
puts "=============================================="
puts "Database Server   : $dbserver"
puts "Database User     : $dbuser"
puts "Database Name     : $dbname"
puts "Warehouses        : $warehouses"
puts "Ramp-up (minutes) : $rampup"
puts "Duration (minutes): $duration"
puts "Virtual Users     : $workload_vusers"
puts "=============================================="

# ---- Schema Build ----
puts "[INFO] Starting schema build..."

dbset db mssqls
diset connection mssqls_server      $dbserver
diset connection mssqls_user        $dbuser
diset connection mssqls_password    $dbpassword
diset connection mssqls_dbase       $dbname

diset tpcc mssqls_server            $dbserver
diset tpcc mssqls_user              $dbuser
diset tpcc mssqls_password          $dbpassword
diset tpcc mssqls_dbase             $dbname
diset tpcc mssqls_authentication    sqlserver
diset tpcc count_ware               $warehouses
diset tpcc total_iterations         1
diset tpcc tpcc_vu                  1
diset tpcc mssqls_driver            odbc

buildschema
waittocomplete

puts "[INFO] Schema build completed successfully."

# ---- Run Workloads ----
foreach vuser $workload_vusers {
    puts "--------------------------------------------------"
    puts "[INFO] Starting workload with $vuser Virtual Users"
    puts "--------------------------------------------------"

    vuset logtotemp 1
    vuset vu $vuser

    loadscript

    vucreate
    vurun
    waittocomplete

    puts "--------------------------------------------------"
    puts "[INFO] Workload with $vuser VUs completed."
    puts "--------------------------------------------------"
}

puts "=============================================="
puts "[INFO] All workloads completed successfully."
puts "=============================================="

exit
