#!/bin/bash

echo "🎉 VaultStream MVP 快速安装"
echo "============================"
echo ""

# 检查Python版本
if ! command -v python3 &> /dev/null; then
    echo "❌ 未找到 Python3，请先安装 Python 3.10+"
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
echo "✅ Python 版本: $PYTHON_VERSION"

# 检查Docker
if ! command -v docker &> /dev/null; then
    echo "⚠️  未找到 Docker，需要手动安装 PostgreSQL 和 Redis"
else
    echo "✅ Docker 已安装"
fi

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

# 启动数据库
echo ""
if command -v docker &> /dev/null; then
    read -p "是否启动 PostgreSQL 和 Redis？(y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🚀 启动数据库服务..."
        docker compose up -d
        echo "✅ 数据库服务已启动"
        echo "   PostgreSQL: localhost:5432"
        echo "   Redis: localhost:6379"
    fi
fi

echo ""
echo "✨ 安装完成！"
echo ""
echo "📝 下一步："
echo "   1. 确保已配置 .env 文件"
echo "   2. 启动后端: python -m app.main"
echo "   3. 启动Bot: python -m app.bot"
echo "   4. 访问: http://localhost:8000"
echo ""
echo "或使用快捷命令:"
echo "   ./start.sh"
echo ""
