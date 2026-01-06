#!/bin/bash

# VaultStream Systemd 服务部署脚本 (通用版)
# 自动检测目录、用户和组，并完成配置替换

set -e

# 获取当前脚本所在目录的上级目录作为项目根目录
PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SERVICE_DIR="/etc/systemd/system"
CURRENT_USER=$(whoami)
CURRENT_GROUP=$(id -gn)

echo "开始部署 VaultStream 服务..."
echo "项目根目录: $PROJECT_ROOT"
echo "运行用户: $CURRENT_USER"
echo "运行组: $CURRENT_GROUP"

# 确保日志目录存在
mkdir -p "$PROJECT_ROOT/logs"
chmod 755 "$PROJECT_ROOT/logs"

# 处理并复制服务文件
deploy_service() {
    local service_name=$1
    local src_file="$PROJECT_ROOT/systemd/$service_name"
    local tmp_file="/tmp/$service_name"

    echo "准备服务文件: $service_name"
    
    # 替换占位符
    sed -e "s|{{PROJECT_ROOT}}|$PROJECT_ROOT|g" \
        -e "s|{{USER}}|$CURRENT_USER|g" \
        -e "s|{{GROUP}}|$CURRENT_GROUP|g" \
        "$src_file" > "$tmp_file"

    echo "安装到 $SERVICE_DIR..."
    sudo cp "$tmp_file" "$SERVICE_DIR/$service_name"
    rm "$tmp_file"
}

deploy_service "vaultstream-api.service"
deploy_service "vaultstream-bot.service"

# 重新加载 systemd
echo "重新加载 systemd 配置..."
sudo systemctl daemon-reload

# 启用并启动主服务
echo "启用并启动服务..."
sudo systemctl enable vaultstream-api
sudo systemctl start vaultstream-api

# 检查服务状态
sudo systemctl status vaultstream-api --no-pager

echo ""
echo "是否启动 Telegram Bot 服务? (y/n)"
read -r -p "> " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    sudo systemctl enable vaultstream-bot
    sudo systemctl start vaultstream-bot
    sudo systemctl status vaultstream-bot --no-pager
else
    echo "跳过启动 Bot 服务。你可以稍后使用 'sudo systemctl start vaultstream-bot' 手动启动。"
fi

echo ""
echo "部署完成！"
echo "查看日志："
echo "   - API/Worker: tail -f $PROJECT_ROOT/logs/vaultstream.log"
echo "   - 系统日志: journalctl -u vaultstream-api -f"
