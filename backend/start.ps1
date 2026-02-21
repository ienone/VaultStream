# VaultStream Windows Start Script

Write-Host "Starting VaultStream (Windows)" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan

# Ensure we are in the script directory so .env is found
Set-Location $PSScriptRoot

# 1. Detect Python Environment
# Priority:
# 1. Local Conda (.venv/python.exe)
# 2. Root Conda (../.venv/python.exe)

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
    from app.core.database import init_db
    async def main():
        await init_db()
        print('Database initialized.')
    asyncio.run(main())
except Exception as e:
    print(f'Init skipped/error: {e}')
"

# 4.5 Auto start Telegram Bot (when primary enabled config exists)
Write-Host "`nChecking Telegram Bot config..." -ForegroundColor Gray
$botCheckOutput = & $PYTHON -c "
import asyncio
import sys
import os
sys.path.append(os.getcwd())
from sqlalchemy import select
from app.core.database import AsyncSessionLocal
from app.models import BotConfig, BotConfigPlatform

async def main():
    async with AsyncSessionLocal() as db:
        enabled_result = await db.execute(
            select(BotConfig).where(
                BotConfig.platform == BotConfigPlatform.TELEGRAM,
                BotConfig.enabled == True,
            )
        )
        enabled_cfgs = enabled_result.scalars().all()

        result = await db.execute(
            select(BotConfig).where(
                BotConfig.platform == BotConfigPlatform.TELEGRAM,
                BotConfig.is_primary == True,
                BotConfig.enabled == True,
            ).limit(1)
        )
        cfg = result.scalar_one_or_none()
        has_primary = bool(cfg and (cfg.bot_token or '').strip())

        enabled_with_token = [c for c in enabled_cfgs if (c.bot_token or '').strip()]
        enabled_primary_count = 1 if has_primary else 0

        print('BOT_AUTOSTART=' + ('1' if has_primary else '0'))
        print('BOT_ENABLED_COUNT=' + str(len(enabled_cfgs)))
        print('BOT_ENABLED_WITH_TOKEN_COUNT=' + str(len(enabled_with_token)))

asyncio.run(main())
"

$botCheckText = ($botCheckOutput | Out-String)
$autoStartBot = $false
if ($botCheckText -match "BOT_AUTOSTART=(\d+)") {
    $autoStartBot = ($matches[1] -eq "1")
}

$enabledCount = 0
if ($botCheckText -match "BOT_ENABLED_COUNT=(\d+)") {
    $enabledCount = [int]$matches[1]
}

$enabledWithTokenCount = 0
if ($botCheckText -match "BOT_ENABLED_WITH_TOKEN_COUNT=(\d+)") {
    $enabledWithTokenCount = [int]$matches[1]
}

if ($autoStartBot) {
    Write-Host "Primary Telegram Bot config detected, starting bot process..." -ForegroundColor Green
    & $PYTHON -m app.services.telegram_bot_service start
} else {
    Write-Host "No enabled primary Telegram Bot config found, skip bot startup." -ForegroundColor DarkGray
    Write-Host "  enabled configs: $enabledCount, enabled with token: $enabledWithTokenCount" -ForegroundColor DarkGray
    if ($enabledWithTokenCount -gt 0) {
        Write-Host "  Hint: there are enabled Telegram configs with token, but none is primary. Activate one as primary in Bot Config page." -ForegroundColor Yellow
    } elseif ($enabledCount -eq 0) {
        Write-Host "  Hint: no enabled Telegram config exists. Create/enable one in Settings -> Bot 管理 -> Bot Config." -ForegroundColor Yellow
    }
}

# 5. Start Application
Write-Host "`nStarting FastAPI..." -ForegroundColor Green

# Read runtime config from settings
$apiHost = & $PYTHON -c "from app.core.config import settings; print(settings.api_host)"
$apiPort = & $PYTHON -c "from app.core.config import settings; print(settings.api_port)"
$debugFlag = & $PYTHON -c "from app.core.config import settings; print('true' if settings.debug else 'false')"

# Launch uvicorn directly so hot-reload behavior is stable
if ($debugFlag -eq "true") {
    Write-Host "Hot reload: enabled" -ForegroundColor Gray
    & $PYTHON "-m" "uvicorn" "app.main:app" "--host" "$apiHost" "--port" "$apiPort" "--reload" "--reload-dir" "$PSScriptRoot\app"
} else {
    Write-Host "Hot reload: disabled (DEBUG=False)" -ForegroundColor Gray
    & $PYTHON "-m" "uvicorn" "app.main:app" "--host" "$apiHost" "--port" "$apiPort"
}
