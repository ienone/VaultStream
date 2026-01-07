#!/bin/bash

echo "VaultStream 依赖安装脚本"
echo "=========================="
echo ""
echo "架构: SQLite + 本地存储 + 任务表队列"
echo "资源: ~200MB 内存占用"
echo ""

# 检查Python版本
if ! command -v python3 &> /dev/null; then
    echo "未找到 Python3，请先安装 Python 3.10+"
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
echo "Python 版本: $PYTHON_VERSION"

# 检查并安装 python3-venv
echo ""
echo "检查虚拟环境支持..."
if ! python3 -m venv --help &> /dev/null; then
    echo "需要安装 python3-venv"
    echo ""
    echo "请运行以下命令安装："
    echo "  sudo apt install python3.12-venv"
    echo ""
    read -p "是否现在安装？(需要sudo权限) (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo apt install python3.12-venv -y
        if [ $? -ne 0 ]; then
            echo "安装失败"
            exit 1
        fi
    else
        echo "无法继续，请手动安装 python3-venv"
        exit 1
    fi
fi

VENV_DIR=".venv"
VENV_PY="$VENV_DIR/bin/python"

# 创建虚拟环境
echo ""
echo "创建虚拟环境 ($VENV_DIR)..."
if [ ! -x "$VENV_PY" ]; then
    # 清理可能损坏的虚拟环境目录
    if [ -d "$VENV_DIR" ]; then
        rm -rf "$VENV_DIR"
    fi

    python3 -m venv "$VENV_DIR"

    if [ -x "$VENV_PY" ]; then
        echo "虚拟环境创建成功"
    else
        echo "虚拟环境创建失败"
        exit 1
    fi
else
    echo "虚拟环境已存在"
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
