#!/bin/bash

# VaultStream 启动脚本

echo "🚀 启动 VaultStream MVP"
echo "======================="

# 检查虚拟环境
if [ ! -d "venv" ]; then
    echo "⚠️  未找到虚拟环境，请先运行 ./install.sh"
    exit 1
fi

# 激活虚拟环境
echo "🔧 激活虚拟环境..."
source venv/bin/activate

# 选择 Python 可执行文件（优先使用虚拟环境）
if [ -n "${VIRTUAL_ENV:-}" ] && [ -x "$VIRTUAL_ENV/bin/python" ]; then
    PYTHON="$VIRTUAL_ENV/bin/python"
elif command -v python >/dev/null 2>&1; then
    PYTHON="$(command -v python)"
elif command -v python3 >/dev/null 2>&1; then
    PYTHON="$(command -v python3)"
else
    echo "❌ 未找到 Python（python/python3）。请先安装 python3（含 venv）后再运行。"
    exit 1
fi
echo "🐍 使用 Python: $PYTHON"

# 创建数据目录（轻量模式需要）
echo "📁 创建数据目录..."
mkdir -p ./data/media
mkdir -p ./logs

# 检查环境配置
if [ ! -f ".env" ]; then
    echo "⚠️  未找到 .env 文件，从示例创建..."
    cp .env.example .env
    echo "✅ 已创建 .env 文件"
    echo ""
    echo "⚠️  请配置以下重要参数："
    echo "   - TELEGRAM_CHANNEL_ID: 你的 Telegram 频道 ID（如 @your_channel）"
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

# 读取部署模式配置
DATABASE_TYPE="$(get_env_value "DATABASE_TYPE")"
QUEUE_TYPE="$(get_env_value "QUEUE_TYPE")"
STORAGE_BACKEND_VALUE="$(get_env_value "STORAGE_BACKEND")"
STORAGE_TYPE="$(get_env_value "STORAGE_TYPE")"
STORAGE_S3_ENDPOINT_VALUE="$(get_env_value "STORAGE_S3_ENDPOINT")"

# 使用默认值
DATABASE_TYPE="${DATABASE_TYPE:-sqlite}"
QUEUE_TYPE="${QUEUE_TYPE:-sqlite}"
STORAGE_TYPE="${STORAGE_TYPE:-local}"

echo ""
echo "🔍 检测到部署模式："
echo "   - 数据库: $DATABASE_TYPE"
echo "   - 队列: $QUEUE_TYPE"
echo "   - 存储: ${STORAGE_TYPE:-${STORAGE_BACKEND_VALUE:-local}}"

# 根据配置决定是否需要 Docker 服务
NEED_POSTGRES=false
NEED_REDIS=false
NEED_MINIO=false

if [ "$DATABASE_TYPE" = "postgresql" ]; then
    NEED_POSTGRES=true
fi

if [ "$QUEUE_TYPE" = "redis" ]; then
    NEED_REDIS=true
fi

# 可选：当使用本机 MinIO 作为 S3 端点时，启动 minio 服务
STORAGE_CHECK="${STORAGE_TYPE:-${STORAGE_BACKEND_VALUE}}"
if [ "${STORAGE_CHECK}" = "s3" ] && echo "${STORAGE_S3_ENDPOINT_VALUE}" | grep -Eq '^(http://)?(127\.0\.0\.1|localhost):9000/?$'; then
    NEED_MINIO=true
    if docker compose ps minio 2>/dev/null | grep -q "Up"; then
        echo "✅ MinIO 已在运行"
    else
        echo ""
        echo "📦 检测到存储后端=s3 且端点为本机，是否启动 MinIO？"
        echo "   - 端点: ${STORAGE_S3_ENDPOINT_VALUE:-http://127.0.0.1:9000}"
        if [ "${AUTO_START_MINIO:-}" = "1" ]; then
            REPLY="y"
        else
            read -p "启动 MinIO？(y/n) " -n 1 -r
            echo
        fi

        if [[ ${REPLY:-} =~ ^[Yy]$ ]]; then
            docker compose up -d minio
            echo "⏳ 等待 MinIO 启动..."
            sleep 3
            if ! docker compose ps minio | grep -q "Up"; then
                echo "❌ MinIO 启动失败，请检查 docker-compose"
                docker compose logs minio
                exit 1
            fi
            echo "✅ MinIO 已启动"
        else
            echo "⚠️  已跳过启动 MinIO（若你使用远端 S3/MinIO，可忽略）"
            NEED_MINIO=false
        fi
    fi
fi

# 启动所需的 Docker 服务
SERVICES_TO_START=""
if [ "$NEED_POSTGRES" = true ]; then
    SERVICES_TO_START="$SERVICES_TO_START postgres"
fi
if [ "$NEED_REDIS" = true ]; then
    SERVICES_TO_START="$SERVICES_TO_START redis"
fi

if [ -n "$SERVICES_TO_START" ]; then
    echo ""
    echo "📦 启动 Docker 服务:$SERVICES_TO_START"
    docker compose up -d $SERVICES_TO_START

    # 等待服务就绪
    echo "⏳ 等待服务启动..."
    sleep 5

    # 检查服务状态
    if ! docker compose ps $SERVICES_TO_START | grep -q "Up"; then
        echo "❌ 服务启动失败，请检查 docker-compose"
        docker compose logs $SERVICES_TO_START
        exit 1
    fi

    echo "✅ Docker 服务已启动"
else
    echo ""
    echo "✅ 轻量模式：无需启动 Docker 服务"
fi

# 运行数据库迁移
echo ""
echo "🔄 初始化数据库..."
"$PYTHON" -c "
import asyncio
from app.database import init_db

async def main():
    await init_db()
    print('✅ 数据库初始化完成')

asyncio.run(main())
" 2>/dev/null || echo "⚠️  数据库表已存在或初始化失败，继续..."

# 启动后端API
echo ""
echo "🌐 启动 FastAPI 后端..."
"$PYTHON" -m app.main &
API_PID=$!

# 等待API启动
sleep 3

echo "✅ 后端API已启动 (PID: $API_PID)"
echo ""
echo "📱 访问地址:"
echo "   - 测试页面: http://localhost:8000"
echo "   - API文档: http://localhost:8000/docs"
echo "   - 交互式API: http://localhost:8000/redoc"
echo ""
echo "💡 下一步:"
echo "   1. 在另一个终端启动 Telegram Bot: $PYTHON -m app.bot"
echo "   2. 或启动后台任务处理: $PYTHON -m app.worker"
echo ""
echo "⚠️  使用 Ctrl+C 停止服务"
echo ""

# 等待用户中断
wait $API_PID