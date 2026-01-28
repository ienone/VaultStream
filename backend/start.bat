@echo off
REM VaultStream 启动脚本 (Windows)

setlocal enabledelayedexpansion

echo 启动 VaultStream
echo ====================
echo.

REM 检查虚拟环境
set VENV_DIR=.venv
set VENV_PY=%VENV_DIR%\Scripts\python.exe

if not exist "%VENV_PY%" (
    echo 错误: 未找到虚拟环境 (%VENV_DIR%)
    echo 请先运行 install.bat
    pause
    exit /b 1
)

echo 使用 Python: %VENV_PY%
echo.

REM 检查环境配置
if not exist ".env" (
    echo 创建配置文件...
    if exist ".env.example" (
        copy ".env.example" ".env" >nul
        echo 已创建 .env 文件
        echo.
        echo 请配置以下重要参数:
        echo    - TELEGRAM_BOT_TOKEN (必需)
        echo    - TELEGRAM_CHANNEL_ID (必需)
        echo.
        set /p EDIT_ENV="是否现在编辑配置？(y/n): "
        if /i "!EDIT_ENV!"=="y" (
            notepad .env
        ) else (
            echo 请编辑 .env 文件并重新运行
            pause
            exit /b 1
        )
    )
)

REM 创建数据目录
echo 创建数据目录...

if not exist "data" mkdir data
if not exist "data\media" mkdir data\media
if not exist "logs" mkdir logs

REM 初始化数据库
echo.
echo 初始化数据库...
"%VENV_PY%" -c "
import asyncio
import sys
import os
sys.path.append(os.getcwd())
try:
    from app.database import init_db
    async def main():
        await init_db()
        print('数据库初始化完成')
    asyncio.run(main())
except Exception as e:
    print(f'数据库表已存在或初始化失败，继续...')
" 2>nul || (
    echo 数据库表已存在或初始化失败，继续...
)

REM 启动 Telegram Bot (可选)
echo.
set /p START_BOT="是否启动 Telegram Bot (需在 .env 配置)? (y/n): "
if /i "%START_BOT%"=="y" (
    echo 正在启动 Telegram Bot...
    start "VaultStream Bot" "%VENV_PY%" -m app.bot.main
)

REM 启动后端API
echo.
echo 启动 FastAPI 后端...
echo.

"%VENV_PY%" -m app.main

pause
