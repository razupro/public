import subprocess
import os
import argparse
import pyodbc
import time
from datetime import datetime

# --- Configuration ---
HAMMERDB_CLI_PATH = "C:\\Program Files\\HammerDB\\hammerdbcli.exe" # Default HammerDB CLI path
# SQLCMD_PATH is no longer strictly needed for DB ops but kept for reference if needed elsewhere.
SQLCMD_PATH = "sqlcmd.exe" # Assumes sqlcmd.exe is in PATH

SCRIPT_ROOT = os.path.dirname(os.path.abspath(__file__))
TCL_SCRIPTS_DIR = os.path.join(SCRIPT_ROOT, "HammerDB_TCL_Scripts")
RESULTS_DIR = os.path.join(SCRIPT_ROOT, "HammerDB_Benchmark_Results")

# --- Functions ---

def run_command(command, check_returncode=True, capture_output=True, display_output=True, error_message="Command failed"):
    """
    Runs a shell command and handles its output and errors.
    """
    try:
        print(f"Executing: {' '.join(command)}")
        process = subprocess.run(command, capture_output=capture_output, text=True, check=False)

        if display_output:
            if process.stdout:
                print(f"STDOUT:\n{process.stdout}")
            if process.stderr:
                print(f"STDERR:\n{process.stderr}")

        if check_returncode and process.returncode != 0:
            print(f"ERROR: {error_message} with exit code {process.returncode}")
            if process.stderr:
                print(f"Error details:\n{process.stderr}")
            raise Exception(f"{error_message} (Exit Code: {process.returncode})")
        
        return process.stdout, process.stderr
    except FileNotFoundError:
        print(f"ERROR: Command not found. Ensure '{command[0]}' is in your system PATH or provide full path.")
        raise
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        raise

def test_sql_connection(server_name, user_name, password, driver="{ODBC Driver 17 for SQL Server}"):
    """
    Tests a basic SQL Server connection using pyodbc.
    """
    conn_str = (
        f"DRIVER={driver};"
        f"SERVER={server_name};"
        f"UID={user_name};"
        f"PWD={password};"
        "Connection Timeout=5;"
    )
    print(f"Attempting SQL connection test to '{server_name}' for user '{user_name}'...")
    try:
        conn = pyodbc.connect(conn_str)
        conn.close()
        print("SQL Connection Test Successful.")
        return True
    except pyodbc.Error as ex:
        sqlstate = ex.args[0]
        print(f"SQL Connection Test Failed to '{server_name}' for user '{user_name}'. Error: {ex}")
        if "08001" in sqlstate: # SQLSTATE 08001: Unable to connect to SQL Server
            print("This often means SQL Server is not running, or network connectivity is blocked.")
        elif "28000" in sqlstate: # SQLSTATE 28000: Invalid authorization specification
            print("This usually means invalid username or password.")
        print(f"Please ensure the ODBC driver '{driver}' is installed and accessible.")
        return False

def execute_sql_with_pyodbc(server_name, user_name, password, query, db_name=None, driver="{ODBC Driver 17 for SQL Server}"):
    """
    Executes a SQL query using pyodbc.
    """
    conn_str = (
        f"DRIVER={driver};"
        f"SERVER={server_name};"
        f"UID={user_name};"
        f"PWD={password};"
    )
    if db_name:
        conn_str += f"DATABASE={db_name};"

    print(f"Executing SQL query via pyodbc (DB: {db_name or 'Default'}): {query}")
    try:
        conn = pyodbc.connect(conn_str, autocommit=True) # autocommit for DDL like DROP/CREATE
        cursor = conn.cursor()
        cursor.execute(query)
        conn.close()
        print("SQL query executed successfully via pyodbc.")
    except pyodbc.Error as ex:
        sqlstate = ex.args[0]
        sql_message = ex.args[1]
        raise Exception(f"SQL Error (State: {sqlstate}): {sql_message} for query: '{query}'")

def get_db_id_pyodbc(server_name, user_name, password, db_name, driver="{ODBC Driver 17 for SQL Server}"):
    """
    Checks if a database exists by getting its DB_ID using pyodbc.
    Returns DB_ID (int) or None.
    """
    conn_str = (
        f"DRIVER={driver};"
        f"SERVER={server_name};"
        f"UID={user_name};"
        f"PWD={password};"
        "DATABASE=master;" # Connect to master to check other DBs
    )
    try:
        conn = pyodbc.connect(conn_str)
        cursor = conn.cursor()
        cursor.execute(f"SELECT DB_ID('{db_name}')")
        result = cursor.fetchone()
        conn.close()
        if result and result[0] is not None:
            return result[0]
        return None
    except pyodbc.Error as ex:
        print(f"WARNING: Could not check DB_ID for '{db_name}'. Error: {ex}")
        return None


def generate_tcl_script(file_name, script_content):
    """
    Generates a TCL script file.
    """
    os.makedirs(TCL_SCRIPTS_DIR, exist_ok=True)
    file_path = os.path.join(TCL_SCRIPTS_DIR, file_name)
    try:
        with open(file_path, "w", encoding="ascii") as f:
            f.write(script_content)
        print(f"Generated TCL script: '{file_path}'")
        return file_path
    except IOError as e:
        raise Exception(f"Failed to generate TCL script '{file_name}'. Error: {e}")

def run_hammerdb_cli(tcl_script_path, output_file=None):
    """
    Runs HammerDB CLI with a specified TCL script using the v5.0 syntax.
    """
    command = [
        HAMMERDB_CLI_PATH,
        "tcl", # Specify that you're running a TCL script
        "auto", # Auto-load the script
        tcl_script_path
    ]
    print(f"Running HammerDB CLI with script: '{tcl_script_path}' (using v5.0 syntax)")

    if output_file:
        # We'll open the output file and pass it directly to subprocess for standard output redirection
        # This is generally more robust for long-running processes than capturing and then writing
        with open(output_file, "w", encoding="utf-8") as f:
            try:
                # Capture stderr to display errors immediately, but direct stdout to file
                process = subprocess.run(command, stdout=f, stderr=subprocess.PIPE, text=True, check=False)
                
                if process.stderr:
                    print(f"HammerDB CLI STDERR:\n{process.stderr}") # Print stderr to console
                
                if process.returncode != 0:
                    print(f"ERROR: HammerDB CLI failed with exit code {process.returncode}. Check '{output_file}' and STDERR above.")
                    raise Exception(f"HammerDB CLI execution failed (Exit Code: {process.returncode})")
                
                return process.stdout, process.stderr # stdout will be empty string as it's redirected to file
            except FileNotFoundError:
                print(f"ERROR: HammerDB CLI not found at '{HAMMERDB_CLI_PATH}'. Please check path.")
                raise
            except Exception as e:
                print(f"An unexpected error occurred while running HammerDB CLI: {e}")
                raise
    else:
        # If no output file is specified, capture and display output directly (for schema build, etc.)
        stdout, stderr = run_command(command)
        return stdout, stderr

# --- Main Script Logic ---
def main():
    parser = argparse.ArgumentParser(description="HammerDB TPC-C Benchmark Script for SQL Server via Python.")
    parser.add_argument("-i", "--instance-name", required=True, help="SQL Server instance name (e.g., 'localhost' or 'localhost\\SQLEXPRESS').")
    parser.add_argument("-p", "--sa-password", required=True, help="SQL Server 'sa' account password. Used for initial setup and user creation.")
    parser.add_argument("-w", "--warehouses", type=int, required=True, help="Number of TPC-C warehouses for schema build and benchmark.")
    parser.add_argument("-v", "--virtual-users", nargs='+', type=int, required=True, help="Space-separated list of Virtual Users (VUs) to test, e.g., 10 20 30.")
    parser.add_argument("-r", "--run-time-seconds", type=int, default=300, help="Duration of each benchmark run in seconds (default: 300).")
    parser.add_argument("-u", "--ramp-up-seconds", type=int, default=60, help="Ramp-up time for each benchmark run in seconds (default: 60).")
    parser.add_argument("--db-name", default="TPCC_HammerDB", help="Name of the TPC-C database to create (default: TPCC_HammerDB).")
    parser.add_argument("--hammerdb-user", default="hammerdb_user", help="Dedicated SQL Server login/user for HammerDB (default: hammerdb_user).")
    parser.add_argument("--hammerdb-user-password", default="HammerDB_User_Password123!", help="Password for the dedicated HammerDB user (default: HammerDB_User_Password123!).")

    args = parser.parse_args()

    print("Starting HammerDB TPC-C Benchmark Script...")

    # Check for HammerDB CLI presence
    if not os.path.exists(HAMMERDB_CLI_PATH):
        print(f"ERROR: HammerDB CLI not found at '{HAMMERDB_CLI_PATH}'. Please ensure HammerDB is installed.")
        exit(1)

    # Test initial SQL Server connection with 'sa'
    if not test_sql_connection(args.instance_name, "sa", args.sa_password):
        print("ERROR: Failed to connect to SQL Server with 'sa' user. Exiting.")
        exit(1)

    # Create output directories
    os.makedirs(TCL_SCRIPTS_DIR, exist_ok=True)
    os.makedirs(RESULTS_DIR, exist_ok=True)

    # --- 1. Drop Database if it exists ---
    print(f"\nAttempting to drop existing database '{args.db_name}' if it exists...")
    # Give a moment for any prior connections to clear
    time.sleep(5) 
    
    db_id = get_db_id_pyodbc(args.instance_name, "sa", args.sa_password, args.db_name)
    if db_id:
        print(f"Database '{args.db_name}' (ID: {db_id}) exists. Attempting to drop it...")
        try:
            # First, set to single user mode and roll back any connections
            execute_sql_with_pyodbc(
                args.instance_name, "sa", args.sa_password,
                f"ALTER DATABASE [{args.db_name}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;",
                db_name="master" # Execute from master context
            )
            # Then drop the database
            execute_sql_with_pyodbc(
                args.instance_name, "sa", args.sa_password,
                f"DROP DATABASE [{args.db_name}];",
                db_name="master" # Execute from master context
            )
            print(f"Database '{args.db_name}' dropped successfully via pyodbc.")
        except Exception as e:
            print(f"ERROR: Failed to drop database '{args.db_name}' via pyodbc. Error: {e}")
            exit(1)
    else:
        print(f"Database '{args.db_name}' does not exist. Skipping drop.")


    # --- 2. Drop user and login if they exist ---
    print(f"\nAttempting to drop existing user '{args.hammerdb_user}' and login if they exist via pyodbc...")
    time.sleep(2) # Small delay for consistency
    try:
        # Drop login (must be in master)
        execute_sql_with_pyodbc(
            args.instance_name, "sa", args.sa_password,
            f"IF EXISTS (SELECT * FROM sys.sql_logins WHERE name = N'{args.hammerdb_user}') DROP LOGIN [{args.hammerdb_user}];",
            db_name="master"
        )
        print(f"Login '{args.hammerdb_user}' dropped (if it existed) via pyodbc.")
        
        # Drop user from the database context if the DB still exists
        db_id_after_drop = get_db_id_pyodbc(args.instance_name, "sa", args.sa_password, args.db_name)
        if db_id_after_drop: # Check if DB exists before trying to drop user in it
            try:
                execute_sql_with_pyodbc(
                    args.instance_name, "sa", args.sa_password,
                    f"IF EXISTS (SELECT * FROM sys.database_principals WHERE name = N'{args.hammerdb_user}') DROP USER [{args.hammerdb_user}];",
                    db_name=args.db_name # Execute in the specific database context
                )
                print(f"User '{args.hammerdb_user}' dropped from database '{args.db_name}' (if existed) via pyodbc.")
            except Exception as e:
                # This is okay if the DB was just dropped and recreated, or user wasn't in it.
                print(f"Note: Could not drop user '{args.hammerdb_user}' from '{args.db_name}' (might not exist in DB, or DB was just dropped). Error: {e}")
        else:
            print(f"Database '{args.db_name}' does not exist, skipping user drop from database.")

        print(f"User '{args.hammerdb_user}' and login cleanup complete.")
    except Exception as e:
        print(f"ERROR: Failed to drop user/login '{args.hammerdb_user}' via pyodbc. Error: {e}")
        exit(1) # Critical failure, exit


    # --- Create new database and HammerDB user ---
    print(f"\nCreating database '{args.db_name}' and login/user '{args.hammerdb_user}' via pyodbc...")
    try:
        # Create database with compatibility level 160 (SQL Server 2022) and Full Recovery
        execute_sql_with_pyodbc(
            args.instance_name, "sa", args.sa_password,
            f"CREATE DATABASE [{args.db_name}]; ALTER DATABASE [{args.db_name}] SET RECOVERY FULL; ALTER DATABASE [{args.db_name}] SET COMPATIBILITY_LEVEL = 160;",
            db_name="master"
        )
        
        # Create SQL Login and User for HammerDB
        execute_sql_with_pyodbc(
            args.instance_name, "sa", args.sa_password,
            f"CREATE LOGIN [{args.hammerdb_user}] WITH PASSWORD = N'{args.hammerdb_user_password}', CHECK_POLICY = OFF;",
            db_name="master" # Create login in master context
        )
        execute_sql_with_pyodbc(
            args.instance_name, "sa", args.sa_password,
            f"CREATE USER [{args.hammerdb_user}] FOR LOGIN [{args.hammerdb_user}]; ALTER ROLE [db_owner] ADD MEMBER [{args.hammerdb_user}];",
            db_name=args.db_name # Create user in the new database context and grant db_owner
        )
        print(f"Database '{args.db_name}' and user '{args.hammerdb_user}' created successfully via pyodbc.")
    except Exception as e:
        print(f"ERROR: Error creating database or user via pyodbc: {e}")
        exit(1)

# --- Generate TCL script for Schema Build ---
    print(f"\nGenerating TCL script for schema build for {args.warehouses} warehouses...")
    schema_build_tcl = f"""
# Set global database and benchmark type using dbset (HammerDB 5.0 strict syntax)
dbset db mssqls

# Set MSSQL connection parameters using diset (HammerDB 5.0 syntax - 'connection' group)
diset connection mssqls_server {args.instance_name}
diset connection mssqls_user {args.hammerdb_user}
diset connection mssqls_password {args.hammerdb_user_password}
diset connection mssqls_authentication sqlserver ; # Authentication is a connection parameter

# Set TPC-C benchmark specific parameters using diset (HammerDB 5.0 syntax - 'tpcc' group)
diset tpcc mssqls_dbase {args.db_name} ; # Database name is a tpcc parameter
diset tpcc tpcc_driver test ; # Use 'test' driver for schema build
diset tpcc count_ware {args.warehouses}
diset tpcc total_iterations 1
diset tpcc tpcc_vu 1 ; # For schema build

loadscript
vuset vu 1 ; # Corrected vuset syntax: 'vuset vu <count>'
vucreate
buildschema
wait for buildschema complete
vudestroy
disconnect
quit
"""
    schema_tcl_file = generate_tcl_script(f"build_schema_{args.warehouses}W.tcl", schema_build_tcl)

    print(f"Running schema build for {args.warehouses} warehouses (this may take some time)...")
    try:
        stdout, stderr = run_hammerdb_cli(schema_tcl_file)
        if "Build of TPCC Schema Complete" in stdout: # A simple check for success phrase
            print(f"Schema build complete for {args.warehouses} warehouses.")
        else:
            print(f"WARNING: Schema build did not report success phrase. Review output: {stdout}\n{stderr}")
            # Consider exiting here if strict success is required
    except Exception as e:
        print(f"ERROR: Error running HammerDB CLI for schema build: {e}")
        exit(1)

    # --- Run Workload with Different Virtual Users ---
    print(f"\nStarting TPC-C benchmark for different Virtual Users: {', '.join(map(str, sorted(args.virtual_users)))}...")

    for vu_count in sorted(args.virtual_users): # Ensure VUs are run in ascending order
        print(f"\n--- Running benchmark with {vu_count} Virtual Users ---")
        
# Generate TCL script for Benchmark Run
        benchmark_run_tcl = f"""
# Set global database and benchmark type using dbset (HammerDB 5.0 strict syntax)
dbset db mssqls


# Set MSSQL connection parameters using diset (HammerDB 5.0 syntax - 'connection' group)
diset connection mssqls_server {args.instance_name}
diset connection mssqls_user {args.hammerdb_user}
diset connection mssqls_password {args.hammerdb_user_password}
diset connection mssqls_authentication sqlserver

# Set TPC-C benchmark specific parameters using diset (HammerDB 5.0 syntax - 'tpcc' group)
diset tpcc mssqls_dbase {args.db_name}
diset tpcc tpcc_driver timed ; # Use 'timed' driver for benchmark run
diset tpcc count_ware {args.warehouses}
diset tpcc total_iterations 1
diset tpcc tpcc_vu {vu_count} ; # Set based on current VU count for the run
diset tpcc mssqls_rampup {args.ramp_up_seconds}
diset tpcc mssqls_duration {args.run_time_seconds}

loadscript
vuset vu {vu_count} ; # Corrected vuset syntax: 'vuset vu <count>'
vucreate
vurun

print vu metrics
vudestroy
disconnect
log off
quit
"""
        benchmark_tcl_file = generate_tcl_script(f"run_benchmark_{args.warehouses}W_{vu_count}VU.tcl", benchmark_run_tcl)
        results_file_name = f"TPCC_Results_{args.warehouses}W_{vu_count}VU_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
        results_file_path = os.path.join(RESULTS_DIR, results_file_name)

        print(f"Executing benchmark for {vu_count} VUs. Results will be saved to: '{results_file_path}'")
        try:
            stdout, stderr = run_hammerdb_cli(benchmark_tcl_file, output_file=results_file_path)
            
            if "TEST RESULT" in stdout or "TPC-C Transactions" in stdout: # Look for key success indicators
                print(f"Benchmark for {vu_count} VUs completed successfully. Results saved to '{results_file_path}'.")
                # Attempt to display key metrics if found in stdout
                for line in stdout.splitlines():
                    if "TPC-C Transactions" in line or "TEST RESULT" in line:
                        print(line)
            else:
                print(f"WARNING: Benchmark for {vu_count} VUs did not report clear success. Check '{results_file_path}' for full details.")
                if stderr:
                    print(f"HammerDB CLI STDERR (partial):\n{stderr[:500]}...") # Print first 500 chars of error
        except Exception as e:
            print(f"ERROR: Error running HammerDB CLI for benchmark: {e}")
        print(f"--- Benchmark for {vu_count} Virtual Users Finished ---")

    print("\nHammerDB TPC-C Benchmark Script Finished.")
    print(f"All generated TCL scripts are in '{TCL_SCRIPTS_DIR}'")
    print(f"All benchmark results are in '{RESULTS_DIR}'")

if __name__ == "__main__":
    main()
