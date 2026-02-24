# 使用官方 Python 轻量镜像
FROM python:3.11-slim

# 设置工作目录
WORKDIR /app

# 设置环境变量
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV DATABASE_TYPE=sqlite
ENV SQLITE_DB_PATH=/app/data/vaultstream.db
ENV QUEUE_TYPE=sqlite
ENV STORAGE_BACKEND=local
ENV STORAGE_LOCAL_ROOT=/app/data/media
# 安全默认值
ENV APP_ENV=prod
ENV DEBUG=False

# 安装系统依赖 (包含 ffmpeg 用于媒体处理)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ffmpeg \
       curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 复制依赖文件
COPY requirements.txt .

# 安装 Python 依赖 + Playwright WebKit（比 Chromium 轻约 200MB，内存低约 50%）
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt \
    && playwright install --with-deps webkit

# 复制项目代码
COPY app /app/app
COPY scripts /app/scripts
COPY systemd /app/systemd
COPY migrations /app/migrations

# 创建数据目录
RUN mkdir -p /app/data/media /app/logs

# 暴露端口
EXPOSE 8000

# 启动命令
CMD ["python", "-m", "app.main"]
