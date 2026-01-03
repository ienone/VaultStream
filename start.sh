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

STORAGE_BACKEND_VALUE="$(get_env_value "STORAGE_BACKEND")"
STORAGE_S3_ENDPOINT_VALUE="$(get_env_value "STORAGE_S3_ENDPOINT")"

# 可选：当使用本机 MinIO 作为 S3 端点时，启动 minio 服务
if [ "${STORAGE_BACKEND_VALUE}" = "s3" ] && echo "${STORAGE_S3_ENDPOINT_VALUE}" | grep -Eq '^(http://)?(127\.0\.0\.1|localhost):9000/?$'; then
    if docker compose ps minio 2>/dev/null | grep -q "Up"; then
        echo "✅ MinIO 已在运行"
    else
        echo ""
        echo "📦 检测到 STORAGE_BACKEND=s3 且端点为本机，是否启动 MinIO？"
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
                echo "❌ MinIO 启动失败，请检查 docker-compose/minio 镜像拉取/代理配置"
                docker compose logs minio
                exit 1
            fi
            echo "✅ MinIO 已启动"
        else
            echo "⚠️  已跳过启动 MinIO（若你使用远端 S3/MinIO，可忽略）"
        fi
    fi
fi

# 启动数据库和Redis
echo ""
echo "📦 启动 PostgreSQL 和 Redis..."
docker compose up -d postgres redis

# 等待服务就绪
echo "⏳ 等待数据库服务启动..."
sleep 5

# 检查服务状态
if ! docker compose ps postgres redis | grep -q "Up"; then
    echo "❌ 数据库服务启动失败，请检查 docker-compose"
    docker compose logs postgres redis
    exit 1
fi

echo "✅ PostgreSQL 和 Redis 已启动"

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