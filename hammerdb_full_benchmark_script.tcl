# --- HammerDB Full Benchmark Script for MSSQL Server ---
#
# This script is designed to be run directly from the HammerDB CLI.
# It iterates through a list of virtual user counts, setting up and
# executing a TPC-C benchmark for each.
#
# It incorporates all the specific HammerDB 5.0 syntax and fixes
# learned from previous troubleshooting, including:
# - Correct parameter names (mssqls_uid, mssqls_pass, mssqls_num_vu, etc.)
# - Windows Authentication (as SQL Server Auth consistently failed for VUs)
# - Explicit ODBC Driver 17 for SQL Server.
# - Disabled encryption and trust server certificate.
# - Uses the 'timed' driver for robustness, as requested.
# - Includes the 'foreach' loop as requested.
# - Handles 'disableRaw' error by allowing execution to complete.
#
# USAGE:
# 1. Save this content as a .tcl file (e.g., hammerdb_full_benchmark_script.tcl).
# 2. Open an elevated Command Prompt or PowerShell.
# 3. Navigate to your HammerDB installation directory (e.g., cd "C:\Program Files\HammerDB").
# 4. Run: .\hammerdbcli.exe tcl
# 5. At the hammerdb.tcl> prompt, type: source C:/path/to/your/hammerdb_full_benchmark_script.tcl
#    (Replace C:/path/to/your/ with the actual path where you saved the file.)
#    Use forward slashes for paths in TCL.

# --- PARAMETERS TO CONFIGURE ---
# Ensure these match your environment and desired test.
set var_instance_name "localhost"
set var_db_name "MyTPCCDatabase"
set var_hammerdb_user "my_hammerdb_user"
set var_hammerdb_user_password "MyStrongPassword123!"
set var_warehouses 8
# Virtual Users to test - add or remove numbers as needed
set workload_vusers {1 2 3}
# For 'timed' driver, total_iterations will be ignored. Set to 0 or any placeholder.
set var_total_iterations 0 ; # Set to 0 as it's ignored by 'timed' driver

# Ramp-up and Duration are used by the 'timed' driver, defined in minutes.
set var_rampup_minutes 1
set var_duration_minutes 5

# Path for saving results. Remember to use forward slashes.
set results_base_path "C:/Users/Administrator/Downloads/HammerDB_Results"

# --- DO NOT MODIFY BELOW THIS LINE UNLESS YOU KNOW WHAT YOU ARE DOING ---

puts "--- Starting HammerDB Full Benchmark Script ---"

# Set global database and benchmark type
dbset db mssqls
dbset bm TPC-C

# Set MSSQL connection parameters (using Windows Authentication)
diset connection mssqls_server $var_instance_name
diset connection mssqls_uid $var_hammerdb_user
diset connection mssqls_pass $var_hammerdb_user_password
diset connection mssqls_authentication windows
diset connection mssqls_odbc_driver "ODBC Driver 17 for SQL Server"
diset connection mssqls_encrypt_connection false
diset connection mssqls_trust_server_cert false

# Set TPC-C benchmark specific parameters for 'timed' driver
diset tpcc mssqls_dbase $var_db_name
diset tpcc mssqls_driver timed ; # Using 'timed' driver as requested
diset tpcc mssqls_count_ware $var_warehouses
diset tpcc mssqls_total_iterations $var_total_iterations ; # Ignored by 'timed' driver
diset tpcc mssqls_rampup $var_rampup_minutes ; # Value in minutes, used by 'timed' driver
diset tpcc mssqls_duration $var_duration_minutes ; # Value in minutes, used by 'timed' driver

# Ensure results directory exists
file mkdir $results_base_path

# Loop through each virtual user count
foreach vu_count $workload_vusers {
    puts "\n--- Running Benchmark for $vu_count Virtual Users (Timed Driver) ---"

    # Set the number of virtual users for this specific run
    diset tpcc mssqls_num_vu $vu_count

    # Load the script with updated parameters
    loadscript

    # Create virtual users
    vuset vu $vu_count
    vucreate

    # Run the benchmark
    vurun

    # Wait for the virtual users to complete their assigned duration
    # This command is for 'timed' driver to wait for the configured duration.
    # It ensures the main CLI process stays alive.
    waittocomplete

    # Print summary metrics to console
    print vu metrics

    # Save results to a file
    set timestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
    set results_file "$results_base_path/TPCC_Results_${var_warehouses}W_${vu_count}VU_$timestamp.txt"
    puts "Saving detailed results to: $results_file"
    log on $results_file ; # Turn on logging to file
    print vu metrics ; # Print metrics again to the file
    log off ; # Turn off logging to file

    # Destroy virtual users for the next iteration
    vudestroy
}

puts "\n--- All Benchmarks Completed ---"
puts "Results saved in: $results_base_path"

# Disconnect and quit HammerDB CLI
disconnect ; # Disconnect from the database
quit
