#!/bin/bash

# VaultStream 完整启动脚本 (Linux/CJK 优化版)

set -e
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. 设置 Linux 输入法环境变量 (解决 Flutter 无法输入中文问题)
# 尝试检测当前输入法框架
if [ -n "$GTK_IM_MODULE" ]; then
    echo "检测到现有 GTK_IM_MODULE=$GTK_IM_MODULE"
else
    # 默认尝试设置为 fcitx (最常见)
    export GTK_IM_MODULE=fcitx
    export QT_IM_MODULE=fcitx
    export XMODIFIERS=@im=fcitx
    echo "已自动注入输入法环境变量 (fcitx)"
fi

# 2. 启动后端
echo "正在启动后端..."
cd "$ROOT_DIR/backend"
if [ ! -d ".venv" ]; then
    echo "未检测到后端环境，正在安装..."
    ./install.sh
fi

# 使用 nohup 后台启动后端，并将日志重定向
nohup ./start.sh > ../backend.log 2>&1 &
BACKEND_PID=$!
echo "后端已在后台启动 (PID: $BACKEND_PID)，日志: backend.log"

# 等待后端端口就绪
echo "等待后端 API 就绪..."
TIMEOUT=30
while ! nc -z localhost 8000; do
  sleep 1
  TIMEOUT=$((TIMEOUT-1))
  if [ $TIMEOUT -le 0 ]; then
      echo "后端启动超时！请检查 backend.log"
      kill $BACKEND_PID
      exit 1
  fi
done
echo "后端已就绪！"

# 3. 启动前端
echo "正在启动前端..."
cd "$ROOT_DIR/frontend"

# 检查是否已编译 linux 版本，如果没有则运行
if [ ! -d "build/linux" ]; then
    echo "首次运行，正在编译 Linux 客户端..."
    flutter build linux
fi

echo "启动 Flutter 客户端..."
flutter run -d linux

# 退出时清理
echo "正在停止服务..."
kill $BACKEND_PID
echo "Done."
