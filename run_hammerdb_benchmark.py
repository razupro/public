import argparse
import subprocess
import os
import pyodbc
import time

def run_sql_query(connection_string, query, db_name="master", autocommit=True):
    """Executes a SQL query against the specified database."""
    conn = None
    try:
        conn_str_with_db = f"{connection_string};DATABASE={db_name};"
        conn = pyodbc.connect(conn_str_with_db, autocommit=autocommit)
        cursor = conn.cursor()
        cursor.execute(query)
        if not autocommit:
            conn.commit()
        print(f"SQL query executed successfully via pyodbc.")
        return True
    except pyodbc.Error as ex:
        sqlstate = ex.args[0]
        print(f"Error executing SQL query via pyodbc: {ex}")
        return False
    finally:
        if conn:
            conn.close()

def main():
    parser = argparse.ArgumentParser(description="Automate HammerDB TPC-C Benchmark for MSSQL Server.")
    parser.add_argument("--instance-name", required=True, help="SQL Server instance name (e.g., 'localhost' or 'localhost\\SQLEXPRESS').")
    parser.add_argument("--sa-password", required=True, help="SQL Server 'sa' account password. Used for initial setup and user creation.")
    parser.add_argument("--db-name", default="MyTPCCDatabase", help="Name of the TPC-C database to create.")
    parser.add_argument("--hammerdb-user", default="my_hammerdb_user", help="Dedicated SQL Server login/user for HammerDB.")
    parser.add_argument("--hammerdb-user-password", default="MyStrongPassword123!", help="Password for the dedicated HammerDB user. MUST be strong.")
    parser.add_argument("--warehouses", type=int, required=True, help="Number of TPC-C warehouses for schema build and benchmark.")
    parser.add_argument("--virtual-users", nargs='+', type=int, required=True, help="List of Virtual Users (VUs) to test, e.g., 10 20 30.")
    parser.add_argument("--run-time-seconds", type=int, default=300, help="Duration of each benchmark run in seconds (default: 300).")
    parser.add_argument("--ramp-up-seconds", type=int, default=60, help="Ramp-up time for each benchmark run in seconds (default: 60).")

    args = parser.parse_args()

    # --- Configuration ---
    # Adjust this path if your HammerDB installation is in a different location
    hammerdb_cli_path = r"C:\Program Files\HammerDB\hammerdbcli.exe"
    tcl_scripts_dir = os.path.join(os.path.expanduser("~"), "Downloads", "HammerDB_TCL_Scripts")
    results_dir = os.path.join(os.path.expanduser("~"), "Downloads", "HammerDB_Results")

    os.makedirs(tcl_scripts_dir, exist_ok=True)
    os.makedirs(results_dir, exist_ok=True)

    odbc_conn_str = f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={args.instance_name};UID=sa;PWD={args.sa_password};"

    print("Starting HammerDB TPC-C Benchmark Script...")

    # --- Step 1: Test SQL Connection (using 'sa' for initial test) ---
    print(f"Attempting SQL connection test to '{args.instance_name}' for user 'sa'...")
    if not run_sql_query(odbc_conn_str, "SELECT 1;", db_name="master"):
        print("ERROR: Initial SQL connection test failed. Please check instance name, 'sa' password, and SQL Server status.")
        return

    # --- Step 2: Drop existing database and user if they exist ---
    print(f"\nAttempting to drop existing database '{args.db_name}' if it exists...")
    # Check if DB exists before trying to drop
    db_exists_query = f"SELECT DB_ID(N'{args.db_name}');"
    db_id = None
    try:
        conn = pyodbc.connect(odbc_conn_str, autocommit=True)
        cursor = conn.cursor()
        cursor.execute(db_exists_query)
        db_id = cursor.fetchone()[0]
        conn.close()
    except pyodbc.Error as ex:
        print(f"Error checking if database exists: {ex}")
        # Continue as it might just not exist
        pass

    if db_id:
        print(f"Database '{args.db_name}' (ID: {db_id}) exists. Attempting to drop it...")
        # Put database in single user mode to drop
        if not run_sql_query(odbc_conn_str, f"ALTER DATABASE [{args.db_name}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;", db_name="master"):
            print(f"ERROR: Failed to set database '{args.db_name}' to SINGLE_USER mode.")
            return
        if not run_sql_query(odbc_conn_str, f"DROP DATABASE [{args.db_name}];", db_name="master"):
            print(f"ERROR: Failed to drop database '{args.db_name}'.")
            return
        print(f"Database '{args.db_name}' dropped successfully via pyodbc.")
    else:
        print(f"Database '{args.db_name}' does not exist, skipping drop.")

    print(f"\nAttempting to drop existing user '{args.hammerdb_user}' and login if they exist via pyodbc...")
    # Drop login
    if not run_sql_query(odbc_conn_str, f"IF EXISTS (SELECT * FROM sys.sql_logins WHERE name = N'{args.hammerdb_user}') DROP LOGIN [{args.hammerdb_user}];", db_name="master"):
        print(f"WARNING: Failed to drop login '{args.hammerdb_user}'. It might not exist or permissions issue.")
    else:
        print(f"Login '{args.hammerdb_user}' dropped (if it existed) via pyodbc.")

    # Drop user from the database if the database still exists or was just created (shouldn't be, but as a safeguard)
    # This part is tricky because the DB might not exist if it was just dropped.
    # We will assume that if the DB was dropped, the user in that DB is also gone.
    # If the DB was NOT dropped (because it didn't exist), then there's no user to drop within it.
    print(f"Database '{args.db_name}' does not exist, skipping user drop from database.")
    print(f"User '{args.hammerdb_user}' and login cleanup complete.")


    # --- Step 3: Create Database and HammerDB User ---
    print(f"\nCreating database '{args.db_name}' and login/user '{args.hammerdb_user}' via pyodbc...")
    # Create DB, set recovery model, and compatibility level
    if not run_sql_query(odbc_conn_str,
                         f"CREATE DATABASE [{args.db_name}]; ALTER DATABASE [{args.db_name}] SET RECOVERY FULL; ALTER DATABASE [{args.db_name}] SET COMPATIBILITY_LEVEL = 160;",
                         db_name="master"):
        print(f"ERROR: Failed to create database '{args.db_name}'.")
        return

    # Create Login
    if not run_sql_query(odbc_conn_str,
                         f"CREATE LOGIN [{args.hammerdb_user}] WITH PASSWORD = N'{args.hammerdb_user_password}', CHECK_POLICY = OFF;",
                         db_name="master"):
        print(f"ERROR: Failed to create login '{args.hammerdb_user}'.")
        return

    # Create User in the new DB and add to db_owner role
    if not run_sql_query(odbc_conn_str,
                         f"CREATE USER [{args.hammerdb_user}] FOR LOGIN [{args.hammerdb_user}]; ALTER ROLE [db_owner] ADD MEMBER [{args.hammerdb_user}];",
                         db_name=args.db_name):
        print(f"ERROR: Failed to create user '{args.hammerdb_user}' or add to 'db_owner' role in database '{args.db_name}'.")
        return
    print(f"Database '{args.db_name}' and user '{args.hammerdb_user}' created successfully via pyodbc.")

# --- Generate TCL script for Schema Build ---
    print(f"\nGenerating TCL script for schema build for {args.warehouses} warehouses...")
    schema_build_tcl = f"""
# Set global database and benchmark type using dbset (HammerDB 5.0 strict syntax)
dbset db mssqls
dbset bm TPC-C

# Set MSSQL connection parameters using diset (HammerDB 5.0 syntax - 'connection' group)
diset connection mssqls_server {args.instance_name}
diset connection mssqls_uid {args.hammerdb_user}
diset connection mssqls_pass {args.hammerdb_user_password}
diset connection mssqls_authentication SQLSEREVR
diset connection mssqls_odbc_driver "ODBC Driver 17 for SQL Server"
diset connection mssqls_encrypt_connection false ; # Disable encryption for testing
diset connection mssqls_trust_server_cert false ; # Disable trust server certificate for testing

# Set TPC-C benchmark specific parameters using diset (HammerDB 5.0 syntax - 'tpcc' group)
diset tpcc mssqls_dbase {args.db_name}
diset tpcc mssqls_driver test ; # Use 'test' driver for schema build
diset tpcc mssqls_count_ware {args.warehouses}
diset tpcc mssqls_total_iterations 1
diset tpcc mssqls_num_vu 1

loadscript
buildschema
quit
"""
    schema_build_tcl_file = os.path.join(tcl_scripts_dir, f"build_schema_{args.warehouses}W.tcl")
    with open(schema_build_tcl_file, "w") as f:
        f.write(schema_build_tcl)
    print(f"Generated TCL script: '{schema_build_tcl_file}'")

    print(f"Running schema build for {args.warehouses} warehouses (this may take some time)...")
    print(f"Running HammerDB CLI with script: '{schema_build_tcl_file}' (using v5.0 syntax)")

    try:
        # Note: Using 'tcl auto' is the standard way to execute a script
        command = [hammerdb_cli_path, "tcl", "auto", schema_build_tcl_file]
        process = subprocess.run(command, capture_output=True, text=True, check=True)
        print("STDOUT:\n", process.stdout)
        if process.stderr:
            print("STDERR:\n", process.stderr)
        print(f"Schema build for {args.warehouses} warehouses completed successfully.")
    except subprocess.CalledProcessError as e:
        print(f"ERROR: Command failed with exit code {e.returncode}")
        print("Error details:\n", e.stderr)
        print("STDOUT (before error):\n", e.stdout)
        print(f"ERROR: Error running HammerDB CLI for schema build: {e}")
        return
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        print(f"ERROR: Error running HammerDB CLI for schema build: {e}")
        return

# Generate TCL script for Benchmark Run
        benchmark_run_tcl = f"""
# Set global database and benchmark type using dbset (HammerDB 5.0 strict syntax)
dbset db mssqls
dbset bm TPC-C

# Set MSSQL connection parameters using diset (HammerDB 5.0 syntax - 'connection' group)
diset connection mssqls_server {args.instance_name}
diset connection mssqls_uid {args.hammerdb_user}
diset connection mssqls_pass {args.hammerdb_user_password}
diset connection mssqls_authentication SQLSEREVR
diset connection mssqls_odbc_driver "ODBC Driver 17 for SQL Server"
diset connection mssqls_encrypt_connection false ; # Disable encryption for testing
diset connection mssqls_trust_server_cert false ; # Disable trust server certificate for testing

# Set TPC-C benchmark specific parameters using diset (HammerDB 5.0 syntax - 'tpcc' group)
diset tpcc mssqls_dbase {args.db_name}
diset tpcc mssqls_driver timed ; # Use 'timed' driver for benchmark run
diset tpcc mssqls_count_ware {args.warehouses}
diset tpcc mssqls_total_iterations 1
diset tpcc mssqls_num_vu {vu_count}
diset tpcc mssqls_rampup {args.ramp_up_seconds}
diset tpcc mssqls_duration {args.run_time_seconds}

loadscript
vuset vu {vu_count}
vucreate
vurun

print vu metrics
vudestroy
log off
quit
"""
        benchmark_tcl_file = os.path.join(tcl_scripts_dir, f"run_benchmark_{args.warehouses}W_{vu_count}VU.tcl")
        with open(benchmark_tcl_file, "w") as f:
            f.write(benchmark_run_tcl)
        print(f"Generated TCL script: '{benchmark_tcl_file}'")

        results_file = os.path.join(results_dir, f"TPCC_Results_{args.warehouses}W_{vu_count}VU_{time.strftime('%Y%m%d_%H%M%S')}.txt")

        print(f"Executing benchmark for {vu_count} VUs. Results will be saved to: '{results_file}'")
        try:
            # Redirect StandardOutput to a file to capture HammerDB's console output (metrics)
            # Using -f with hammerdbcli auto is typical for script execution
            benchmark_command = [hammerdb_cli_path, "tcl", "auto", benchmark_tcl_file]
            with open(results_file, "w") as outfile:
                process = subprocess.run(benchmark_command, stdout=outfile, stderr=subprocess.PIPE, text=True, check=True)
            
            print(f"Benchmark for {vu_count} VUs completed successfully. Results saved to '{results_file}'.")
            
            # Print relevant metrics from the results file to console
            with open(results_file, "r") as f:
                for line in f:
                    if "TPC-C Transactions" in line or "Total transactions" in line or "tpm" in line:
                        print(line.strip())

        except subprocess.CalledProcessError as e:
            print(f"WARNING: Benchmark for {vu_count} VUs failed with exit code {e.returncode}. Check '{results_file}' for full details.")
            if e.stderr:
                print("STDERR from HammerDB CLI:\n", e.stderr)
        except Exception as e:
            print(f"Error running HammerDB CLI for benchmark: {e}")
        print(f"--- Benchmark for {vu_count} Virtual Users Finished ---\n")

    print("HammerDB TPC-C Benchmark Script Finished.")
    print(f"All generated TCL scripts are in '{tcl_scripts_dir}'")
    print(f"All benchmark results are in '{results_dir}'")

if __name__ == "__main__":
    main()
