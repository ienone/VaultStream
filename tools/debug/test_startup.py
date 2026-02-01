import subprocess
import time
import sys
import os

# Hardcoded absolute path for verification in this specific environment
python_exe = r"C:\Users\86138\Documents\coding\VaultStream\.venv\Scripts\python.exe"

if not os.path.exists(python_exe):
    print(f"Warning: {python_exe} not found, falling back to sys.executable")
    python_exe = sys.executable

print(f"Using python: {python_exe}")

try:
    # Start the process
    process = subprocess.Popen(
        [python_exe, "-m", "app.main"], 
        cwd=".", 
        stdout=subprocess.PIPE, 
        stderr=subprocess.PIPE, 
        text=True,
        env={**os.environ, "PYTHONPATH": "."}
    )
    
    print("Process started, waiting 10s...")
    # Wait a bit
    time.sleep(10)
    
    # Check if it's still running
    if process.poll() is None:
        print("Process is running successfully (alive after 10s).")
        process.terminate()
        try:
            outs, errs = process.communicate(timeout=5)
            print("--- STDOUT (Last 1000 chars) ---")
            print(outs[-1000:] if outs else "(none)")
            print("--- STDERR (Last 1000 chars) ---")
            print(errs[-1000:] if errs else "(none)")
        except subprocess.TimeoutExpired:
            process.kill()
            print("Process killed.")
    else:
        print(f"Process exited prematurely with code {process.returncode}")
        outs, errs = process.communicate()
        print("--- STDOUT ---")
        print(outs)
        print("--- STDERR ---")
        print(errs)

except Exception as e:
    print(f"Execution Error: {e}")