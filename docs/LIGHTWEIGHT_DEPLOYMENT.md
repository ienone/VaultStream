# VaultStream 轻量化部署指南

## 概述

VaultStream 当前采用轻量化架构，无需复杂的Docker配置和外部服务依赖。

## 架构特点

### 核心组件

1. **数据库**: SQLite（WAL模式）
   - 单文件存储，易于备份
   - WAL模式支持并发读写
   - 64MB缓存 + mmap优化
   - JSON字段支持

2. **任务队列**: SQLite Task表
   - 使用`SELECT FOR UPDATE SKIP LOCKED`实现原子性
   - 无需额外Redis服务
   - 支持优先级和重试机制

3. **媒体存储**: 本地文件系统
   - SHA256内容寻址
   - 2级目录分片（`ab/cd/hash.webp`）
   - WebP图片转码（默认质量80）

### 资源占用

- 内存: ~200MB
- 存储: 取决于内容量
  - SQLite数据库: ~10MB（千条内容）
  - 媒体文件: 取决于图片数量和质量

### 适用场景

✅ **适合**:
- 个人内容收藏
- 小团队协作（<10人）
- 单机部署环境
- 低流量应用（<1000次/天API调用）

❌ **不适合**:
- 高并发场景（>100 req/s）
- 多节点分布式部署
- 需要独立扩展队列/存储的场景

## 部署步骤

### 1. 环境准备

```bash
# 克隆代码
git clone <repository>
cd VaultStream

# 进入后端目录
cd backend

# 创建Python虚拟环境
python3 -m venv .venv
source .venv/bin/activate

# 安装依赖
pip install -r requirements.txt
```

### 2. 配置环境变量

```bash
cp .env.example .env
```

编辑`.env`文件：

```dotenv
# 数据库配置
DATABASE_TYPE=sqlite
SQLITE_DB_PATH=./data/vaultstream.db

# 任务队列配置
QUEUE_TYPE=sqlite

# 存储配置
STORAGE_BACKEND=local
STORAGE_LOCAL_ROOT=./data/media
STORAGE_PUBLIC_BASE_URL=http://localhost:8000/api/v1

# 媒体处理
ENABLE_ARCHIVE_MEDIA_PROCESSING=True
ARCHIVE_IMAGE_WEBP_QUALITY=80
ARCHIVE_IMAGE_MAX_COUNT=100

# Telegram Bot（可选）
# Bot 账号通过 API 创建：POST /api/v1/bot-config
# 并设置 is_primary=true 后再启动 app.bot.main

# 代理配置（如需访问被墙平台）
HTTP_PROXY=http://127.0.0.1:7890

# API配置
API_HOST=0.0.0.0
API_PORT=8000
DEBUG=False
LOG_LEVEL=INFO
```

### 3. 启动服务

```bash
# 旧版本升级：迁移历史 bot_runtime / bot_chats 到 BotConfig 归属
cd backend
python -m migrations.m14_bind_bot_chats_to_config

# 使用启动脚本（推荐）
cd ..
./start.sh

# 或手动启动
cd backend
source .venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### 4. 启动Telegram Bot（可选）

在另一个终端：

先确保已经创建并激活主 Telegram BotConfig：

```bash
curl -X POST http://localhost:8000/api/v1/bot-config \
   -H "Content-Type: application/json" \
   -H "X-API-Token: <your_api_token>" \
   -d '{"platform":"telegram","name":"main-bot","bot_token":"<token>","enabled":true,"is_primary":true}'
```

```bash
cd backend
source .venv/bin/activate
python -m app.bot.main
```

## 数据目录结构

```
VaultStream/
├── data/
│   ├── vaultstream.db          # SQLite数据库
│   ├── vaultstream.db-shm      # WAL共享内存
│   ├── vaultstream.db-wal      # WAL日志
│   └── media/                  # 媒体文件存储
│       ├── ab/
│       │   └── cd/
│       │       └── abcdef123...webp
│       └── ...
└── logs/                       # 应用日志
```

## 性能优化

### SQLite优化

系统已自动应用以下优化：

```python
# WAL模式
PRAGMA journal_mode = WAL

# 缓存大小64MB
PRAGMA cache_size = -65536

# 启用mmap
PRAGMA mmap_size = 268435456

# 外键约束
PRAGMA foreign_keys = ON

# 同步级别
PRAGMA synchronous = NORMAL

# 临时文件内存存储
PRAGMA temp_store = MEMORY
```

### 建议索引

```sql
-- 平台和创建时间组合索引
CREATE INDEX IF NOT EXISTS idx_contents_platform_created 
ON contents(platform, created_at DESC);

-- 状态索引
CREATE INDEX IF NOT EXISTS idx_contents_status 
ON contents(status);

-- 平台ID索引
CREATE INDEX IF NOT EXISTS idx_contents_platform_id 
ON contents(platform_id);
```

### 文件系统优化

```bash
# 使用SSD存储媒体文件
# 定期清理未引用的文件

# 检查存储使用
du -sh data/media

# 统计文件数量
find data/media -type f | wc -l
```

## 备份策略

### 数据库备份

```bash
# 方法1: 直接复制（需先停止服务）
cp data/vaultstream.db data/vaultstream.db.backup

# 方法2: SQLite在线备份
sqlite3 data/vaultstream.db ".backup data/vaultstream.db.backup"

# 方法3: 导出SQL
sqlite3 data/vaultstream.db .dump > backup.sql
```

### 媒体文件备份

```bash
# 打包媒体目录
tar -czf media-backup-$(date +%Y%m%d).tar.gz data/media/

# 同步到远程
rsync -avz data/media/ backup-server:/backup/vaultstream/media/
```

### 自动化备份脚本

```bash
#!/bin/bash
# backup.sh

BACKUP_DIR="/path/to/backup"
DATE=$(date +%Y%m%d_%H%M%S)

# 备份数据库
sqlite3 data/vaultstream.db ".backup $BACKUP_DIR/db_$DATE.db"

# 备份媒体（增量）
rsync -av --delete data/media/ $BACKUP_DIR/media/

# 保留最近7天备份
find $BACKUP_DIR -name "db_*.db" -mtime +7 -delete

echo "Backup completed: $DATE"
```

## 监控和维护

### 健康检查

```bash
# API健康检查
curl http://localhost:8000/health

# 数据库完整性检查
sqlite3 data/vaultstream.db "PRAGMA integrity_check"

# 检查WAL文件大小
ls -lh data/vaultstream.db-wal
```

### 日志查看

```bash
# 实时查看日志
tail -f logs/app.log

# 查看错误日志
grep ERROR logs/app.log

# 按时间过滤
grep "2026-01-06" logs/app.log
```

### 性能监控

```bash
# 查看数据库大小
sqlite3 data/vaultstream.db "SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size();"

# 查看表大小
sqlite3 data/vaultstream.db "SELECT name, SUM(pgsize) as size FROM dbstat GROUP BY name ORDER BY size DESC;"

# 查看慢查询（需启用DEBUG模式）
grep "elapsed_ms" logs/app.log | awk '{if($NF > 1000) print}'
```

## 故障排查

### 常见问题

#### 1. 数据库锁定

**症状**: `database is locked`错误

**解决**:
```bash
# 检查WAL模式
sqlite3 data/vaultstream.db "PRAGMA journal_mode"

# 如果不是WAL，切换到WAL
sqlite3 data/vaultstream.db "PRAGMA journal_mode=WAL"
```

#### 2. 磁盘空间不足

**症状**: 写入失败

**解决**:
```bash
# 检查磁盘使用
df -h

# 清理WAL文件
sqlite3 data/vaultstream.db "PRAGMA wal_checkpoint(TRUNCATE)"

# 清理未引用的媒体文件
python tools/cleanup_orphan_media.py
```

#### 3. 内存不足

**症状**: 进程被OOM killer杀死

**解决**:
- 降低`PRAGMA cache_size`
- 减少并发worker数量
- 限制`ARCHIVE_IMAGE_MAX_COUNT`

## 迁移到生产环境

如果未来需要扩展到PostgreSQL/Redis/S3：

1. 代码已保留适配器抽象层
2. 可从git历史恢复生产模式实现
3. 参考文件：
   - `app/db_adapter.py`
   - `app/queue_adapter.py`
   - `app/storage.py`

## 相关文档

- [架构设计](ARCHITECTURE.md)
- [数据库设计](DATABASE.md)
- [API文档](API.md)
