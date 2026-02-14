@echo off
REM VaultStream 依赖安装脚本 (Windows)
REM 支持系统 Python、Conda 或本地虚拟环境

setlocal enabledelayedexpansion

echo VaultStream 依赖安装脚本 (Windows)
echo ====================================
echo.

REM 自动检测可用的 Python 环境
echo 检测可用的 Python 环境...
set AVAILABLE_PYTHON=
set AVAILABLE_CONDA=

REM 检查系统 Python (支持 python3 及避免 Windows Store 快捷方式)
set AVAILABLE_PYTHON=
for %%p in (python python3) do (
    if "!AVAILABLE_PYTHON!"=="" (
        %%p -c "import sys; print(f'Python {sys.version_info.major}.{sys.version_info.minor}')" >"%temp%\py_version.txt" 2>&1
        if !errorlevel! equ 0 (
            set /p PY_VERSION=<"%temp%\py_version.txt"
            set AVAILABLE_PYTHON=%%p (!PY_VERSION!)
            echo   ✓ 系统 Python: !PY_VERSION!
        )
        del /f /q "%temp%\py_version.txt" >nul 2>&1
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

REM 检查 & 安装 ffmpeg
echo.
echo 检查 ffmpeg (可选，用于快速转码动画GIF)...
set FFMPEG_INSTALLED=0
ffmpeg -version >nul 2>&1
if errorlevel 0 (
    set FFMPEG_INSTALLED=1
    echo   ✓ ffmpeg 已安装
)

if !FFMPEG_INSTALLED! equ 0 (
    echo   ✗ ffmpeg 未找到，尝试用 winget 自动安装...
    echo.
    
    REM 尝试用 winget
    winget --version >nul 2>&1
    if errorlevel 0 (
        echo   检测到 winget，执行安装命令...
        winget install -e --id Gyan.FFmpeg --accept-source-agreements --accept-package-agreements
        if errorlevel 0 (
            echo   ✓ ffmpeg 安装命令执行成功
            echo   [提示] 当前窗口的 PATH 可能未更新，将继续进行 Python 依赖安装
            echo   [提示] 如后续需要 ffmpeg 加速，请在新终端窗口中验证 (ffmpeg -version^)
        ) else (
            echo   ✗ winget 安装失败
        )
    ) else (
        echo   ✗ winget 未找到
    )
    
    if !FFMPEG_INSTALLED! equ 0 (
        echo.
        echo   [手动方式] 安装 ffmpeg:
        echo   1. 访问官网: https://ffmpeg.org/download.html
        echo   2. 下载并运行安装程序
        echo   3. 确保选择 "Add FFmpeg to PATH" 选项
        echo   4. 如未选择，手动添加 ffmpeg.exe 所在目录到 PATH:
        echo      - 右键 "此电脑" -^> 属性
        echo      - 点击 "高级系统设置"
        echo      - 点击 "环境变量"
        echo      - 编辑 PATH，添加 ffmpeg 目录 (如 C:\ffmpeg\bin^)
        echo.
    )
)

echo.
echo 安装模式选择:
if not "!AVAILABLE_PYTHON!"=="" (
    echo   1. 使用系统 Python (!AVAILABLE_PYTHON!)
)
if not "!AVAILABLE_CONDA!"=="" (
    echo   2. 使用 Conda 创建虚拟环境 (vaultstream_env)
)
echo   3. 创建本地虚拟环境 (vaultstream_env)
echo.

set /p CHOICE="请选择 (默认 3): "
if "!CHOICE!"=="" set CHOICE=3

if "!CHOICE!"=="1" (
    set VENV_DIR=
    set VENV_PY=python
    set INSTALL_MODE=system
) else if "!CHOICE!"=="2" if not "!AVAILABLE_CONDA!"=="" (
    set VENV_DIR=vaultstream_env
    set INSTALL_MODE=conda
    echo.
    echo 创建 Conda 虚拟环境...
    conda create -n vaultstream_env python=3.11 -y
    for /f "tokens=*" %%i in ('conda run -n vaultstream_env python -c "import sys; print(sys.executable)"') do set VENV_PY=%%i
) else (
    set VENV_DIR=vaultstream_env
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
        echo Telegram Bot 账号请在服务启动后通过 /api/v1/bot-config 创建
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

if !FFMPEG_INSTALLED! equ 0 (
    echo [提示] FFmpeg 未在当前窗口中找到。
    echo 如果上述 winget 安装成功，请在新终端窗口中运行脚本，
    echo 或验证: ffmpeg -version
    echo.
)

echo 下一步:
echo    1. 确保已配置 .env 文件
echo    2. 启动服务: start.bat
echo.
pause
