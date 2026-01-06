#!/bin/bash

echo "🎉 VaultStream 轻量化安装"
echo "=========================="
echo ""
echo "📦 架构: SQLite + 本地存储 + 任务表队列"
echo "💾 资源: ~200MB 内存占用"
echo ""

# 检查Python版本
if ! command -v python3 &> /dev/null; then
    echo "❌ 未找到 Python3，请先安装 Python 3.10+"
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
echo "✅ Python 版本: $PYTHON_VERSION"

# 检查并安装 python3-venv
echo ""
echo "📦 检查虚拟环境支持..."
if ! python3 -m venv --help &> /dev/null; then
    echo "⚠️  需要安装 python3-venv"
    echo ""
    echo "请运行以下命令安装："
    echo "  sudo apt install python3.12-venv"
    echo ""
    read -p "是否现在安装？(需要sudo权限) (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo apt install python3.12-venv -y
        if [ $? -ne 0 ]; then
            echo "❌ 安装失败"
            exit 1
        fi
    else
        echo "❌ 无法继续，请手动安装 python3-venv"
        exit 1
    fi
fi

# 创建虚拟环境
echo ""
echo "📦 创建虚拟环境..."
if [ ! -d "venv" ] || [ ! -f "venv/bin/activate" ]; then
    # 清理可能损坏的venv目录
    if [ -d "venv" ]; then
        rm -rf venv
    fi
    
    python3 -m venv venv
    
    if [ $? -eq 0 ] && [ -f "venv/bin/activate" ]; then
        echo "✅ 虚拟环境创建成功"
    else
        echo "❌ 虚拟环境创建失败"
        exit 1
    fi
else
    echo "✅ 虚拟环境已存在"
fi

# 激活虚拟环境
echo ""
echo "🔧 激活虚拟环境..."
source venv/bin/activate

if [ $? -ne 0 ]; then
    echo "❌ 虚拟环境激活失败"
    exit 1
fi

# 安装依赖
echo ""
echo "📥 安装Python依赖..."
pip install --upgrade pip
pip install -r requirements.txt

if [ $? -eq 0 ]; then
    echo "✅ 依赖安装成功"
else
    echo "❌ 依赖安装失败"
    exit 1
fi

# 创建配置文件
echo ""
if [ ! -f ".env" ]; then
    echo "⚙️  创建配置文件..."
    cp .env.example .env
    echo "✅ 已创建 .env 文件"
    echo ""
    echo "⚠️  请编辑 .env 文件，配置以下参数："
    echo "   - TELEGRAM_BOT_TOKEN (必需)"
    echo "   - TELEGRAM_CHANNEL_ID (必需)"
    echo ""
    read -p "是否现在编辑配置文件？(y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ${EDITOR:-nano} .env
    fi
else
    echo "✅ 配置文件已存在"
fi

# 创建数据目录
echo ""
echo "📁 创建数据目录..."
mkdir -p ./data/media
mkdir -p ./logs
echo "✅ 数据目录已创建"
echo "   - SQLite数据库: ./data/vaultstream.db"
echo "   - 媒体存储: ./data/media/"
echo "   - 日志文件: ./logs/"

echo ""
echo "✨ 安装完成！"
echo ""
echo "📝 下一步："
echo "   1. 确保已配置 .env 文件（特别是 TELEGRAM_BOT_TOKEN）"
echo "   2. 启动服务: ./start.sh"
echo "   3. 访问API文档: http://localhost:8000/docs"
echo ""
echo "💡 提示："
echo "   - 轻量模式无需 Docker"
echo "   - 数据存储在 ./data/ 目录"
echo "   - 定期备份 ./data/ 目录即可"
echo ""
