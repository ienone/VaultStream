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
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
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
COPY requirements.txt constraints.txt ./

# 安装 Python 依赖 + Playwright WebKit
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt \
    && playwright install --with-deps webkit

# 复制项目代码
COPY app /app/app
COPY systemd /app/systemd

# 创建运行用户和数据目录
RUN groupadd --system vaultstream \
    && useradd --system --gid vaultstream --home-dir /app --shell /usr/sbin/nologin vaultstream \
    && mkdir -p /app/data/media /app/logs \
    && chown -R vaultstream:vaultstream /app /ms-playwright

# 暴露端口
EXPOSE 8000

USER vaultstream

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8000/api/v1/health || exit 1

# 启动命令
CMD ["python", "-m", "app.main"]
