#!/bin/bash

# VaultStream 启动脚本

echo "启动 VaultStream"
echo "======================="

VENV_DIR=".venv"
PYTHON="$VENV_DIR/bin/python"

# 检查虚拟环境
VENV_DIR=".venv"
if [ -d "vaultstream_env" ]; then
    VENV_DIR="vaultstream_env"
fi

PYTHON="$VENV_DIR/bin/python"

if [ ! -x "$PYTHON" ]; then
    echo " 未找到虚拟环境 ($VENV_DIR)，请先运行 ./install.sh"
    exit 1
fi

echo "使用 Python: $PYTHON"

# 检查环境配置
if [ ! -f ".env" ]; then
    echo " 未找到 .env 文件，从示例创建..."
    cp .env.example .env
    echo "已创建 .env 文件"
    echo ""
    echo " 请配置 API_TOKEN、数据库与存储参数"
    echo " Bot 账号在服务启动后通过 /api/v1/bot-config 创建"
    echo ""
    read -p "是否现在编辑配置？(y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ${EDITOR:-nano} .env
    else
        echo "请稍后编辑 .env 文件并重新运行"
        exit 1
    fi
fi

get_env_value() {
    local key="$1"
    # 读取 .env 文件中的键值对，忽略注释行
    #
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
    value="$(get_env_value "$key")"
    echo "${value:-$default_value}"
}

# 创建数据目录（轻量模式需要）
echo "创建数据目录..."

SQLITE_DB_PATH="$(get_env_or_default "SQLITE_DB_PATH" "./data/vaultstream.db")"
STORAGE_LOCAL_ROOT="$(get_env_or_default "STORAGE_LOCAL_ROOT" "./data/media")"
API_HOST="$(get_env_or_default "API_HOST" "0.0.0.0")"
API_PORT="$(get_env_or_default "API_PORT" "8000")"
STORAGE_PUBLIC_BASE_URL="$(get_env_or_default "STORAGE_PUBLIC_BASE_URL" "")"

mkdir -p "$(dirname "$SQLITE_DB_PATH")"
mkdir -p "$STORAGE_LOCAL_ROOT"
mkdir -p ./logs

# 读取并验证配置
DATABASE_TYPE="$(get_env_value "DATABASE_TYPE")"
QUEUE_TYPE="$(get_env_value "QUEUE_TYPE")"
STORAGE_BACKEND="$(get_env_value "STORAGE_BACKEND")"

# 使用默认值
DATABASE_TYPE="${DATABASE_TYPE:-sqlite}"
QUEUE_TYPE="${QUEUE_TYPE:-sqlite}"
STORAGE_BACKEND="${STORAGE_BACKEND:-local}"

echo ""
echo "检测到配置："
echo "   - 数据库: $DATABASE_TYPE"
echo "   - 队列: $QUEUE_TYPE"
echo "   - 存储: $STORAGE_BACKEND"

# 验证配置（当前仅支持轻量模式）
if [ "$DATABASE_TYPE" != "sqlite" ]; then
    echo ""
    echo " 警告: 当前仅支持 SQLite 数据库"
    echo "   请将 .env 中的 DATABASE_TYPE 设置为 sqlite"
    echo ""
    read -p "是否继续？(可能导致启动失败) (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

if [ "$QUEUE_TYPE" != "sqlite" ]; then
    echo ""
    echo " 警告: 当前仅支持 SQLite 任务队列"
    echo "   请将 .env 中的 QUEUE_TYPE 设置为 sqlite"
    echo ""
    read -p "是否继续？(可能导致启动失败) (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

if [ "$STORAGE_BACKEND" != "local" ]; then
    echo ""
    echo " 警告: 当前仅支持本地文件存储"
    echo "   请将 .env 中的 STORAGE_BACKEND 设置为 local"
    echo ""
    read -p "是否继续？(可能导致启动失败) (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""
echo "轻量模式：无需 Docker 服务"

# 运行数据库迁移
echo ""
echo "初始化数据库..."
"$PYTHON" -c "
import asyncio
from app.database import init_db

async def main():
    await init_db()
    print('数据库初始化完成')

asyncio.run(main())
" 2>/dev/null || echo "数据库表已存在或初始化失败，继续..."

# 检查端口是否被占用
if lsof -Pi :"$API_PORT" -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    echo " 端口 $API_PORT 已被占用，正在停止旧进程..."
    lsof -ti:"$API_PORT" | xargs kill -9 2>/dev/null || true
    sleep 1
fi

# 启动后端API
echo ""
echo "启动 FastAPI 后端..."
"$PYTHON" -m app.main &
API_PID=$!

# 等待API启动
sleep 3

echo "后端API已启动 (PID: $API_PID)"
echo ""
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

echo "参考访问地址:"
echo "   - 测试页面: $API_BASE_URL"
echo "   - API文档: $API_BASE_URL/docs"
echo "   - 交互式API: $API_BASE_URL/redoc"
echo "   - 媒体API: $MEDIA_BASE_URL/{key}"
echo ""
echo "下一步:"
echo "   1. 先创建主 BotConfig，再启动 Telegram Bot: $PYTHON -m app.bot.main"
echo "   2. 或启动后台任务处理: $PYTHON -m app.worker"
echo ""
echo " 使用 Ctrl+C 停止服务"
echo ""

# 等待用户中断
wait $API_PID
echo ""
echo "查看实时日志: tail -f logs/vaultstream.log"
echo ""
echo "数据位置:"
echo "   - SQLite数据库: $SQLITE_DB_PATH"
echo "   - 媒体文件: $STORAGE_LOCAL_ROOT"
echo "   - 日志文件: ./logs/"