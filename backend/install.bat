@echo off
REM VaultStream 依赖安装脚本 (Windows)
REM 支持系统 Python、Conda 或本地虚拟环境

setlocal enabledelayedexpansion

echo VaultStream 依赖安装脚本 (Windows)
echo ====================================
echo.
echo 架构: SQLite + 本地存储 + 任务表队列
echo 资源: ~200MB 内存占用
echo.

REM 自动检测可用的 Python 环境
echo 检测可用的 Python 环境...
set AVAILABLE_PYTHON=
set AVAILABLE_CONDA=

REM 检查系统 Python
python --version >nul 2>&1
if errorlevel 0 (
    for /f "tokens=2" %%i in ('python --version 2^>^&1') do (
        set PYTHON_VERSION=%%i
        set AVAILABLE_PYTHON=python (!PYTHON_VERSION!)
        echo   ✓ 系统 Python: !PYTHON_VERSION!
    )
)

REM 检查 Conda
conda --version >nul 2>&1
if errorlevel 0 (
    set AVAILABLE_CONDA=conda
    echo   ✓ Conda 环境管理器已安装
)

REM 如果没有找到 Python，则失败
if "!AVAILABLE_PYTHON!"=="" (
    echo 错误: 未找到 Python，请先安装 Python 3.10+
    echo 访问: https://www.python.org/downloads/
    pause
    exit /b 1
)

echo.
echo 安装模式选择:
if not "!AVAILABLE_PYTHON!"=="" (
    echo   1. 使用系统 Python (!AVAILABLE_PYTHON!)
)
if not "!AVAILABLE_CONDA!"=="" (
    echo   2. 使用 Conda 创建虚拟环境 (vaultwarden_env)
)
echo   3. 创建本地虚拟环境 (vaultwarden_env)
echo.

set /p CHOICE="请选择 (默认 3): "
if "!CHOICE!"=="" set CHOICE=3

if "!CHOICE!"=="1" (
    set VENV_DIR=
    set VENV_PY=python
    set INSTALL_MODE=system
) else if "!CHOICE!"=="2" if not "!AVAILABLE_CONDA!"=="" (
    set VENV_DIR=vaultwarden_env
    set INSTALL_MODE=conda
    echo.
    echo 创建 Conda 虚拟环境...
    conda create -n vaultwarden_env python=3.11 -y
    for /f "tokens=*" %%i in ('conda run -n vaultwarden_env python -c "import sys; print(sys.executable)"') do set VENV_PY=%%i
) else (
    set VENV_DIR=vaultwarden_env
    set INSTALL_MODE=venv
    set VENV_PY=!VENV_DIR!\Scripts\python.exe
)

echo.
echo 使用 Python: !VENV_PY!
echo 虚拟环境目录: !VENV_DIR!
echo.

REM 创建虚拟环境（仅在 venv 模式时）
if "!INSTALL_MODE!"=="venv" (
    if exist "!VENV_DIR!" (
        echo 虚拟环境已存在，跳过创建
    ) else (
        echo 创建虚拟环境...
        python -m venv "!VENV_DIR!"
        
        if not exist "!VENV_PY!" (
            echo 错误: 虚拟环境创建失败
            pause
            exit /b 1
        )
        echo 虚拟环境创建成功
    )
)

REM 检查 pip 并安装依赖
echo.
echo 升级 pip 和安装依赖...
"!VENV_PY!" -m pip install --upgrade pip --quiet
"!VENV_PY!" -m pip install -r requirements.txt

if errorlevel 1 (
    echo 错误: 依赖安装失败
    pause
    exit /b 1
)

echo 依赖安装成功
echo.

REM 创建配置文件
if not exist ".env" (
    echo 创建配置文件...
    if exist ".env.example" (
        copy ".env.example" ".env" >nul
        echo 已创建 .env 文件
        echo.
        echo Telegram Bot 配置 (可选，仅在 ENABLE_BOT=True 时需要):
        echo    - TELEGRAM_BOT_TOKEN (可选)
        echo    - TELEGRAM_CHANNEL_ID (可选)
        echo.
        set /p EDIT_ENV="是否现在用编辑器打开 .env 文件？(y/n): "
        if /i "!EDIT_ENV!"=="y" (
            notepad .env
        )
    )
) else (
    echo 配置文件已存在
)

REM 创建数据目录
echo.
echo 创建数据目录...

if not exist "data" mkdir data
if not exist "data\media" mkdir data\media
if not exist "logs" mkdir logs

echo 数据目录已创建
echo    - SQLite数据库: ./data/vaultstream.db
echo    - 媒体存储: ./data/media/
echo    - 日志目录: ./logs/

echo.
echo ============================================
echo 安装完成！
echo.
echo 下一步:
echo    1. 确保已配置 .env 文件
echo    2. 启动服务: start.bat
echo.
pause
