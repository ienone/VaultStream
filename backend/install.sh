#!/bin/bash

echo "VaultStream 依赖安装脚本 (Linux/macOS)"
echo "=========================================="
echo ""
echo "架构: SQLite + 本地存储 + 任务表队列"
echo "资源: ~200MB 内存占用"
echo ""

# 自动检测可用的 Python
echo "检测可用的 Python 环境..."
AVAILABLE_PYTHON=""
AVAILABLE_CONDA=""

# 检查系统 Python3 (3.10+)
if command -v python3 &> /dev/null; then
    if python3 -c 'import sys; exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
        PY_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))' 2>/dev/null)
        AVAILABLE_PYTHON="python3 ($PY_VERSION)"
        echo "  ✓ 系统 Python3: $PY_VERSION"
    fi
fi

# 检查 Conda
if command -v conda &> /dev/null; then
    AVAILABLE_CONDA="conda"
    echo "  ✓ Conda 环境管理器已安装"
fi

# 如果没有找到任何 Python，则失败
if [ -z "$AVAILABLE_PYTHON" ]; then
    echo "错误: 未找到 Python 3.10+，请先安装"
    exit 1
fi

echo ""
echo "检查 ffmpeg (可选，用于快速转码动画GIF)..."
FFMPEG_AVAILABLE="no"
if command -v ffmpeg &> /dev/null; then
    echo "  ✓ ffmpeg 已安装"
    FFMPEG_AVAILABLE="yes"
else
    echo "  ✗ ffmpeg 未找到，尝试自动安装..."
    OS_TYPE=$(uname -s)
    
    if [ "$OS_TYPE" = "Darwin" ]; then
        # macOS - brew
        if command -v brew &> /dev/null; then
            brew install ffmpeg
            if command -v ffmpeg &> /dev/null; then
                echo "  ✓ ffmpeg 安装成功"
                FFMPEG_AVAILABLE="yes"
            fi
        fi
    elif [ "$OS_TYPE" = "Linux" ]; then
        # Linux - apt 或 yum
        if command -v apt &> /dev/null; then
            echo "  检测到 apt，准备安装 ffmpeg，可能需要输入密码..."
            if sudo apt update && sudo apt install -y ffmpeg 2>/dev/null; then
                if command -v ffmpeg &> /dev/null; then
                    echo "  ✓ ffmpeg 安装成功"
                    FFMPEG_AVAILABLE="yes"
                fi
            else
                echo "  ✗ apt 安装失败，可能需要管理员权限"
            fi
        elif command -v yum &> /dev/null; then
            echo "  检测到 yum，准备安装 ffmpeg，可能需要输入密码..."
            if sudo yum install -y ffmpeg 2>/dev/null; then
                if command -v ffmpeg &> /dev/null; then
                    echo "  ✓ ffmpeg 安装成功"
                    FFMPEG_AVAILABLE="yes"
                fi
            else
                echo "  ✗ yum 安装失败，可能需要管理员权限"
            fi
        fi
    fi
    
    if [ "$FFMPEG_AVAILABLE" = "no" ]; then
        echo "  [可选] 手动安装 ffmpeg:"
        if [ "$OS_TYPE" = "Darwin" ]; then
            echo "    brew install ffmpeg"
        elif [ "$OS_TYPE" = "Linux" ]; then
            echo "    Ubuntu/Debian: sudo apt install ffmpeg"
            echo "    Fedora/CentOS: sudo yum install ffmpeg"
        fi
    fi
fi

echo ""
echo "安装模式选择:"
if [ -n "$AVAILABLE_PYTHON" ]; then
    echo "  1. 使用系统 Python ($AVAILABLE_PYTHON)"
fi
if [ -n "$AVAILABLE_CONDA" ]; then
    echo "  2. 使用 Conda 创建虚拟环境 (vaultstream_env)"
fi
echo "  3. 创建本地虚拟环境 (vaultstream_env)"
echo ""

# 设置默认选择
if [ -n "$AVAILABLE_CONDA" ]; then
    DEFAULT_CHOICE=2
else
    DEFAULT_CHOICE=3
fi

read -p "请选择 (默认 $DEFAULT_CHOICE): " -n 1 -r CHOICE
echo
CHOICE=${CHOICE:-$DEFAULT_CHOICE}

if [ "$CHOICE" = "1" ]; then
    # 使用系统 Python
    VENV_DIR=""
    VENV_PY="python3"
    INSTALL_MODE="system"
elif [ "$CHOICE" = "2" ] && [ -n "$AVAILABLE_CONDA" ]; then
    # 使用 Conda 创建虚拟环境
    VENV_DIR="vaultstream_env"
    INSTALL_MODE="conda"
    echo ""
    echo "创建 Conda 虚拟环境..."
    conda create -n "$VENV_DIR" python=3.11 -y
    VENV_PY="$(conda run -n $VENV_DIR which python)"
    if [ -z "$VENV_PY" ]; then
        echo "错误: Conda 虚拟环境创建失败"
        exit 1
    fi
else
    # 创建本地虚拟环境
    VENV_DIR="vaultstream_env"
    INSTALL_MODE="venv"
fi

echo ""
echo "使用 Python: $VENV_PY"
echo "虚拟环境目录: ${VENV_DIR:-(系统全局)}"

# 创建虚拟环境（仅在 venv 模式时）
if [ "$INSTALL_MODE" = "venv" ]; then
    echo ""
    echo "创建虚拟环境 ($VENV_DIR)..."
    
    # 检查虚拟环境支持
    if ! python3 -m venv --help &> /dev/null; then
        echo "错误: 需要安装 python3-venv"
        echo ""
        echo "请运行:"
        echo "  sudo apt install python3-venv"
        exit 1
    fi
    
    if [ ! -d "$VENV_DIR" ]; then
        python3 -m venv "$VENV_DIR"
        if [ -x "$VENV_DIR/bin/python" ]; then
            echo "虚拟环境创建成功"
            VENV_PY="$VENV_DIR/bin/python"
        else
            echo "虚拟环境创建失败"
            exit 1
        fi
    else
        echo "虚拟环境已存在"
    fi
fi

# 确保 venv 内有 pip（某些发行版可能 venv 不包含 pip）
if ! "$VENV_PY" -c "import pip" >/dev/null 2>&1; then
    echo ""
    echo "检测到虚拟环境缺少 pip，尝试修复 (ensurepip)..."
    "$VENV_PY" -m ensurepip --upgrade
fi

# 安装依赖
echo ""
echo "安装Python依赖..."
"$VENV_PY" -m pip install --upgrade pip
"$VENV_PY" -m pip install -r requirements.txt

if [ $? -eq 0 ]; then
    echo "依赖安装成功"
else
    echo "依赖安装失败"
    exit 1
fi

# 创建配置文件
echo ""
if [ ! -f ".env" ]; then
    echo "创建配置文件..."
    cp .env.example .env
    echo "已创建 .env 文件"
    echo ""
    echo "请编辑 .env 文件，配置以下参数："
    echo "   - TELEGRAM_BOT_TOKEN (必需)"
    echo "   - TELEGRAM_CHANNEL_ID (必需)"
    echo ""
    read -p "是否现在编辑配置文件？(y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ${EDITOR:-nano} .env
    fi
else
    echo "配置文件已存在"
fi

# 将Python路径写入.env
echo ""
echo "配置Python路径..."
if [ -f ".env" ]; then
    # 移除旧的PYTHON_PATH配置 (兼容 Linux/macOS sed)
    grep -v "^PYTHON_PATH=" .env > .env.tmp && mv .env.tmp .env
else
    touch .env
fi

# 添加新的PYTHON_PATH
echo "PYTHON_PATH=$VENV_PY" >> .env
echo "已将 Python 路径写入 .env: PYTHON_PATH=$VENV_PY"

# 读取 .env 配置（用于创建目录与展示提示信息）
get_env_value() {
    local key="$1"
    awk -F= -v k="$key" '
        $0 ~ /^[[:space:]]*#/ { next }
        $1 ~ "^[[:space:]]*"k"[[:space:]]*$" {
            v=$0
            sub(/^[^=]*=/, "", v)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
            print v
            exit
        }
    ' .env
}

get_env_or_default() {
    local key="$1"
    local default_value="$2"
    local value=""
    if [ -f ".env" ]; then
        value="$(get_env_value "$key")"
    fi
    echo "${value:-$default_value}"
}

echo ""
echo "创建数据目录..."

SQLITE_DB_PATH="$(get_env_or_default "SQLITE_DB_PATH" "./data/vaultstream.db")"
STORAGE_LOCAL_ROOT="$(get_env_or_default "STORAGE_LOCAL_ROOT" "./data/media")"
API_HOST="$(get_env_or_default "API_HOST" "0.0.0.0")"
API_PORT="$(get_env_or_default "API_PORT" "8000")"
STORAGE_PUBLIC_BASE_URL="$(get_env_or_default "STORAGE_PUBLIC_BASE_URL" "")"

mkdir -p "$(dirname "$SQLITE_DB_PATH")"
mkdir -p "$STORAGE_LOCAL_ROOT"
mkdir -p ./logs

ACCESS_HOST="$API_HOST"
if [ "$ACCESS_HOST" = "0.0.0.0" ]; then
    ACCESS_HOST="localhost"
fi

API_BASE_URL="http://$ACCESS_HOST:$API_PORT"
if [ -n "$STORAGE_PUBLIC_BASE_URL" ]; then
    MEDIA_BASE_URL="$STORAGE_PUBLIC_BASE_URL"
else
    MEDIA_BASE_URL="$API_BASE_URL/api/v1/media"
fi

echo "数据目录已创建"
echo "   - SQLite数据库: $SQLITE_DB_PATH"
echo "   - 媒体存储: $STORAGE_LOCAL_ROOT"
echo "   - 日志目录: ./logs/"
echo "   - API地址: $API_BASE_URL"
echo "   - API文档: $API_BASE_URL/docs"
echo "   - 媒体API: $MEDIA_BASE_URL/{key}"

echo ""
echo "安装完成！"
echo ""
echo "下一步："
echo "   1. 确保已配置 .env 文件"
echo "   2. 启动服务: ./start.sh"
echo ""
