# HammerDB TCL Benchmark Script - Auto Generated

set dbserver      "{DBSERVER}"
set dbuser        "{DBUSER}"
set dbpassword    "{DBPASSWORD}"
set dbname        "tpcc"

set warehouses    {WAREHOUSES}
set workload_vusers {{{VUS}}}
set rampup        2
set duration      {DURATION}

puts "=============================================="
puts "Database Server   : $dbserver"
puts "Database User     : $dbuser"
puts "Database Name     : $dbname"
puts "Warehouses        : $warehouses"
puts "Ramp-up (minutes) : $rampup"
puts "Duration (minutes): $duration"
puts "Virtual Users     : $workload_vusers"
puts "=============================================="

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

puts "[INFO] Schema build completed."

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
