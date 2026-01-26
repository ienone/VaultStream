# VaultStream Windows Start Script

Write-Host "Starting VaultStream (Windows)" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan

# Ensure we are in the script directory so .env is found
Set-Location $PSScriptRoot

# 1. Detect Python Environment
# Priority:
# 1. Local Conda (.venv/python.exe)
# 2. Root Conda (../.venv/python.exe)
# 3. Local Venv (.venv/Scripts/python.exe)
# 4. Root Venv (../.venv/Scripts/python.exe)

$paths = @(
    "$PSScriptRoot\.venv\python.exe",
    "$PSScriptRoot\..\.venv\python.exe",
    "$PSScriptRoot\.venv\Scripts\python.exe",
    "$PSScriptRoot\..\.venv\Scripts\python.exe"
)

$PYTHON = $null
$VENV_DIR = $null

foreach ($p in $paths) {
    if (Test-Path $p) {
        $PYTHON = $p
        # Get parent directory of python.exe or Scripts/..
        if ($p -match "Scripts\\python.exe") {
            $VENV_DIR = (Get-Item $p).Directory.Parent.FullName
        } else {
            $VENV_DIR = (Get-Item $p).Directory.FullName
        }
        break
    }
}

if (-not $PYTHON) {
    Write-Host " Error: Virtual environment not found." -ForegroundColor Red
    Write-Host " Checked paths:"
    $paths | ForEach-Object { Write-Host "   - $_" -ForegroundColor Gray }
    Write-Host "`n Please create a virtual environment first."
    exit 1
}

Write-Host "Using Python: $PYTHON" -ForegroundColor Gray
Write-Host "Venv Dir:     $VENV_DIR" -ForegroundColor Gray

# 2. Setup Environment Variables
$env:PYTHONPATH = $PSScriptRoot
$env:PIP_NO_CONFIG_FILE = "1"
$env:PIP_ISOLATED = "1"

# 3. Check .env
if (-not (Test-Path "$PSScriptRoot\.env")) {
    if (Test-Path "$PSScriptRoot\.env.example") {
        Copy-Item "$PSScriptRoot\.env.example" "$PSScriptRoot\.env"
        Write-Host " Created .env from example." -ForegroundColor Yellow
    } else {
        Write-Host " Warning: No .env detection." -ForegroundColor Yellow
    }
}

# 4. Initialize Database (Lightweight)
Write-Host "`nInitializing database..." -ForegroundColor Gray
& $PYTHON -c "
import asyncio
import sys
import os
sys.path.append(os.getcwd())
try:
    from app.database import init_db
    async def main():
        await init_db()
        print('Database initialized.')
    asyncio.run(main())
except Exception as e:
    print(f'Init skipped/error: {e}')
"

# 5. Start Application
Write-Host "`nStarting FastAPI..." -ForegroundColor Green
$cmdString = "$PYTHON -m app.main"

# We use Start-Process to keep it in this window or spawn visible
# Ideally keeping it attached is better for logs
# But 'python' usually requires -u for unbuffered in some shells.
# Let's just run it directly.

Invoke-Expression $cmdString
