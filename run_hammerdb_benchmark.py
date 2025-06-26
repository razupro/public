import subprocess
import os
import argparse
import pyodbc # Required for SQL connection testing, though sqlcmd is used for most operations
import time
from datetime import datetime

# --- Configuration ---
HAMMERDB_CLI_PATH = "C:\\Program Files\\HammerDB\\hammerdbcli.exe" # Default HammerDB CLI path
# Ensure SQLCMD.exe is in your system PATH or provide its full path here
# SQLCMD_PATH = "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe"
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

def invoke_sqlcmd_command(server_instance, user_name, password, query):
    """
    Executes a SQL query using sqlcmd.exe.
    """
    command = [
        SQLCMD_PATH,
        "-S", server_instance,
        "-U", user_name,
        "-P", password,
        "-Q", query
    ]
    print(f"Executing SQLCMD query: {query}")
    stdout, stderr = run_command(command, error_message=f"SQLCMD command failed for query: '{query}'")
    return stdout, stderr

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
    Runs HammerDB CLI with a specified TCL script.
    """
    command = [
        HAMMERDB_CLI_PATH,
        "-f", tcl_script_path
    ]
    print(f"Running HammerDB CLI with script: '{tcl_script_path}'")

    if output_file:
        with open(output_file, "w", encoding="utf-8") as f:
            stdout, stderr = run_command(command, capture_output=True, display_output=False, check_returncode=False)
            f.write("STDOUT:\n")
            if stdout:
                f.write(stdout)
            f.write("\nSTDERR:\n")
            if stderr:
                f.write(stderr)
            
            # Re-run command to check return code (subprocess.run with check=True is usually better but this allows separate output capture)
            # For simplicity, we assume if output_file is provided, we just capture and check outside if needed
            # A more robust approach would be to process process.stdout/stderr directly.
            # Here, we will just use the initial run_command's check_returncode
        return stdout, stderr
    else:
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
    # Add a small delay to ensure any lingering connections from previous tests are cleared.
    time.sleep(5) 
    try:
        stdout_db_drop, stderr_db_drop = invoke_sqlcmd_command( # Capture output
            args.instance_name, "sa", args.sa_password,
            f"ALTER DATABASE [{args.db_name}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; IF DB_ID('{args.db_name}') IS NOT NULL DROP DATABASE [{args.db_name}];"
        )
        print(f"Database '{args.db_name}' drop attempt completed. SQLCMD Output (if any):\nSTDOUT:\n{stdout_db_drop}\nSTDERR:\n{stderr_db_drop}")
        print(f"Database '{args.db_name}' dropped (if it existed).")
    except Exception as e:
        print(f"ERROR: Failed to drop database '{args.db_name}'. This is often due to active connections or permissions. Please ensure no one else is connected. Error: {e}")
        # Exit here, as database operations are critical for benchmark
        exit(1)


    # --- 2. Drop user and login if they exist ---
    print(f"\nAttempting to drop existing user '{args.hammerdb_user}' and login if they exist...")
    # Add a small delay again for good measure
    time.sleep(2)
    try:
        # Drop login (must be in master)
        stdout_login_drop, stderr_login_drop = invoke_sqlcmd_command(
            args.instance_name, "sa", args.sa_password,
            f"USE [master]; IF EXISTS (SELECT * FROM sys.sql_logins WHERE name = N'{args.hammerdb_user}') DROP LOGIN [{args.hammerdb_user}];"
        )
        print(f"Login '{args.hammerdb_user}' drop attempt completed. SQLCMD Output (if any):\nSTDOUT:\n{stdout_login_drop}\nSTDERR:\n{stderr_login_drop}")

        # Drop user (in target DB context, if DB exists)
        # This will fail if the DB was just dropped and recreated, but that's fine.
        # This is more for cases where only the user/login needs cleaning.
        try:
            stdout_user_drop, stderr_user_drop = invoke_sqlcmd_command(
                args.instance_name, "sa", args.sa_password,
                f"USE [{args.db_name}]; IF EXISTS (SELECT * FROM sys.database_principals WHERE name = N'{args.hammerdb_user}') DROP USER [{args.hammerdb_user}];"
            )
            print(f"User '{args.hammerdb_user}' drop attempt in DB '{args.db_name}' completed. SQLCMD Output (if any):\nSTDOUT:\n{stdout_user_drop}\nSTDERR:\n{stderr_user_drop}")
        except Exception as e:
            # If the DB was just dropped, this will correctly fail, so just log it as a note.
            print(f"Note: Could not drop user '{args.hammerdb_user}' in '{args.db_name}' (database might not exist or user was not in that DB). Error: {e}")
        print(f"User '{args.hammerdb_user}' and login dropped (if they existed).")
    except Exception as e:
        print(f"ERROR: Failed to drop user/login '{args.hammerdb_user}'. Error: {e}")
        exit(1) # Critical failure, exit

    # --- Create new database and HammerDB user ---
    print(f"\nCreating database '{args.db_name}' and login/user '{args.hammerdb_user}'...")
    try:
        # Create database with compatibility level 160 (SQL Server 2022) and Full Recovery
        invoke_sqlcmd_command(
            args.instance_name, "sa", args.sa_password,
            f"CREATE DATABASE [{args.db_name}]; ALTER DATABASE [{args.db_name}] SET RECOVERY FULL; ALTER DATABASE [{args.db_name}] SET COMPATIBILITY_LEVEL = 160;"
        )
        
        # Create SQL Login and User for HammerDB
        invoke_sqlcmd_command(
            args.instance_name, "sa", args.sa_password,
            f"CREATE LOGIN [{args.hammerdb_user}] WITH PASSWORD = N'{args.hammerdb_user_password}', CHECK_POLICY = OFF; USE [{args.db_name}]; CREATE USER [{args.hammerdb_user}] FOR LOGIN [{args.hammerdb_user}]; ALTER ROLE [db_owner] ADD MEMBER [{args.hammerdb_user}];"
        )
        print(f"Database '{args.db_name}' and user '{args.hammerdb_user}' created successfully.")
    except Exception as e:
        print(f"ERROR: Error creating database or user: {e}")
        exit(1)

    # --- Generate TCL script for Schema Build ---
    print(f"\nGenerating TCL script for schema build for {args.warehouses} warehouses...")
    schema_build_tcl = f"""
# Connect to SQL Server
dbset db sqlserver
dbset server {args.instance_name}
dbset inst {args.instance_name}
dbset user {args.hammerdb_user}
dbset password {args.hammerdb_user_password}
dbset tpcc
dbset tpcc_driver tcl
dbset tpcc_warehouses {args.warehouses}

# Build Schema
vuser auto
vu 1 ; # Only 1 virtual user is needed for schema build
buildschema
wait for buildschema complete
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
# Connect to SQL Server
dbset db sqlserver
dbset server {args.instance_name}
dbset inst {args.instance_name}
dbset user {args.hammerdb_user}
dbset password {args.hammerdb_user_password}
dbset tpcc
dbset tpcc_driver tcl
dbset tpcc_warehouses {args.warehouses}

# Benchmark run
vuser auto
vuser {vu_count}
load tpc-c
timer {args.run_time_seconds}
rampup {args.ramp_up_seconds}
print vu metrics
disconn
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
