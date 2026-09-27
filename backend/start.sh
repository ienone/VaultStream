#!/usr/bin/env sh
set -eu

unset CDPATH
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
PYTHON="$SCRIPT_DIR/../.venv/bin/python"

if [ ! -x "$PYTHON" ]; then
    echo "找不到仓库虚拟环境 Python：$PYTHON" >&2
    echo "请先在仓库根目录创建 .venv 并安装 backend/requirements-dev.txt。" >&2
    exit 1
fi

cd "$SCRIPT_DIR"
exec "$PYTHON" -m app.main
