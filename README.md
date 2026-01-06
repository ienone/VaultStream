# VaultStream - 跨平台收藏夹&分享工具

## 项目目的：VaultStream

VaultStream 是多平台内容存档与分享系统。通过爬取存档和结构化分发，实现一个信息存档与分享的平台。

记录链接，通过深度适配器抓取并本地化存储（包含链接、图、文、数据信息、视频(tbd)、音频(tbd)、评论数据(tbd)）。结合RAG技术等，实现对存档内容的AI摘要与语义检索。用户可通过移动端应用和Web后台进行内容管理与分享。

### 1. 设计构想：解耦

- 多维适配架构： 采用解耦的插件化设计，开发者可快速为不同平台编写专属适配器，实现URL净化与元数据提取。
- 多端交互体验： 
    - 移动端 (MD3 Expressive)： 基于 Material 3 规范开发，支持通过系统分享快捷收藏/打标，支持查看管理/检索/收藏内容并管理
    - 管理后台 (Web)： 和移动端同步开发，支持批量导入/导出、标签管理、AI 摘要生成等高级功能。

- 自动化分发网络： 结合 Astrbot 等机器人框架，支持基于标签的轨道式推送，实现 QQ/TG 等多平台的定时、定向分享。

### 2. 安全与合规网关

严格区分私有存档与分享：

- 私有库： 存储全量信息，不支持分享
- 合规分享： 分享卡片形式，仅包含标题、摘要、封面图等

## 项目结构

```text
app/
├── adapters/          # 平台解析适配器 (B站, X等)
├── api.py             # FastAPI 路由定义
├── bot.py             # Telegram Bot 逻辑
├── models.py          # SQLAlchemy 数据库模型
├── worker.py          # 异步抓取任务处理器
├── db_adapter.py      # 数据库适配器抽象层
├── queue_adapter.py   # 队列适配器抽象层
├── storage.py         # 存储后端抽象层
└── utils.py           # 工具函数 (URL规范化, 文本格式化)
docs/                  # 详细文档
```

## 使用方法

### 架构特点

VaultStream 采用**轻量化架构**：

- **数据库**: SQLite（WAL模式，性能优化）
- **任务队列**: SQLite Task表（使用`SELECT FOR UPDATE SKIP LOCKED`）
- **媒体存储**: 本地文件系统 + SHA256内容寻址
- **资源占用**: ~200MB 内存

### 持久化运行 (Systemd)

对于 Linux 服务器，可以使用 systemd 将 VaultStream 作为服务运行，确保后台自动重启并持久化执行：

1. **部署服务**:
   ```bash
   ./scripts/deploy_services.sh
   ```

2. **管理命令**:
   - 启动 API: `sudo systemctl start vaultstream-api`
   - 查看日志: `tail -f logs/vaultstream.log`
   - 检查状态: `sudo systemctl status vaultstream-api`

### 日志系统

项目现已支持自动写入日志文件：
- 文本日志: `logs/vaultstream.log`
- JSON日志: `logs/vaultstream.json.log` (适合日志聚合)
- 支持自动按天/大小切换、压缩及保留 7 天记录。
- **部署要求**: 无需Docker，单机部署

**适用场景**: 个人/小团队内容收藏与分享

> **扩展性说明**: 代码保留了适配器抽象层（DatabaseAdapter, QueueAdapter, StorageBackend），如需扩展到PostgreSQL/Redis/S3等生产级组件，可参考git历史重新实现。

### 快速开始

#### 1. 安装依赖

```bash
./install.sh
```

#### 2. 配置环境

```bash
cp .env.example .env  # 配置环境变量
```

关键配置：

```dotenv
# 数据库（SQLite）
DATABASE_TYPE=sqlite
SQLITE_DB_PATH=./data/vaultstream.db

# 任务队列（SQLite）
QUEUE_TYPE=sqlite

# 存储后端（本地）
STORAGE_BACKEND=local
STORAGE_LOCAL_ROOT=./data/media

# 媒体处理
ENABLE_ARCHIVE_MEDIA_PROCESSING=True
ARCHIVE_IMAGE_WEBP_QUALITY=80
ARCHIVE_IMAGE_MAX_COUNT=100
```

#### 3. 启动服务

```bash
./start.sh
```

服务将在 `http://localhost:8000` 启动。

访问地址：
- 测试页面: http://localhost:8000
- API文档: http://localhost:8000/docs
- 交互式API: http://localhost:8000/redoc

#### 4. 健康检查

```bash
curl http://localhost:8000/health
```

### 功能特性

#### 私有归档媒体处理（图片→WebP→存储）

该功能仅作用于私有归档（`Content.raw_metadata.archive`），不会进入对外分享卡片字段。

**配置**：
```dotenv
ENABLE_ARCHIVE_MEDIA_PROCESSING=True
ARCHIVE_IMAGE_WEBP_QUALITY=80        # WebP质量（1-100）
ARCHIVE_IMAGE_MAX_COUNT=100          # 单个内容最多处理图片数
```

**存储位置**：
- 本地路径：`./data/media/`
- 目录结构：SHA256内容寻址 + 2级分片
- 示例：`data/media/ab/cd/abcdef123...webp`

**处理流程**：
1. Worker在内容解析成功后自动触发
2. 下载远程图片 → Pillow转WebP → 计算SHA256
3. 存储到本地文件系统（内容寻址）
4. 更新`raw_metadata.archive.images[].stored_*`字段

**访问方式**：
- API代理：`GET /api/v1/media/{key}`
- 直接访问：`./data/media/{hash[0:2]}/{hash[2:4]}/{hash}.webp`

**补处理失败图片**：
```bash
# 重新触发同一内容的解析任务，系统会自动检测并补处理未存储的图片
curl -X POST http://localhost:8000/api/v1/shares \
  -H "Content-Type: application/json" \
  -d '{"url": "原URL"}'
```

#### 导出内容为Markdown

导出脚本读取`Content.raw_metadata.archive`，生成包含本地图片引用的Markdown文件：

```bash
# 基础导出
./venv/bin/python tests/export_markdown.py --content-id 6 --out exports/content_6.md

# 导出前补处理缺失图片（推荐）
./venv/bin/python tests/export_markdown.py \
  --content-id 6 \
  --out exports/content_6.md \
  --process-missing-images \
  --max-images 100
```

## 核心API

### 1. 创建分享

```bash
curl -X POST http://localhost:8000/api/v1/shares \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://www.bilibili.com/video/BV1xx411c7mD",
    "tags": ["技术", "教程"],
    "note": "值得收藏",
    "is_nsfw": false
  }'
```

### 2. 获取待分发内容

```bash
curl -X POST http://localhost:8000/api/v1/bot/get-content \
  -H "Content-Type: application/json" \
  -d '{
    "target_platform": "TG_CHANNEL_@example",
    "platform": "bilibili",
    "limit": 5
  }'
```

### 3. 标记已推送

```bash
curl -X POST http://localhost:8000/api/v1/bot/mark-pushed \
  -H "Content-Type: application/json" \
  -d '{
    "content_id": 123,
    "target_platform": "TG_CHANNEL_@example",
    "message_id": "456"
  }'
```

### 4. 查询内容详情

```bash
curl http://localhost:8000/api/v1/contents/123
```

### 5. 访问存储的图片

```bash
# 通过API代理访问
curl http://localhost:8000/api/v1/media/blobs/sha256/ab/cd/abcdef123...webp

# 或直接访问文件系统
cat ./data/media/ab/cd/abcdef123...webp
```

## Telegram Bot

### 启动Bot

```bash
./venv/bin/python -m app.bot
```

### Bot命令

- `/start` - 开始使用
- `/get [tag]` - 拉取未推送内容（可选指定tag过滤）
- `/status` - 查看系统状态
- `/stats` - 查看统计信息

### 配置

在`.env`中配置：

```dotenv
ENABLE_BOT=True
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_CHANNEL_ID=@your_channel_id
```

## 数据存储说明

### 元数据存储（SQLite）

**位置**: `./data/vaultstream.db`

**表结构**:
- `contents`: 内容主表（标题、URL、作者、统计数据等）
- `content_sources`: 分享来源记录
- `pushed_records`: 推送记录
- `tasks`: 异步任务队列

**优化配置**:
- WAL模式：支持并发读写
- 64MB缓存
- mmap启用
- 外键约束

### 媒体文件存储（本地文件系统）

**位置**: `./data/media/`

**目录结构**: SHA256内容寻址 + 2级分片
```
./data/media/
├── ab/                    # 哈希前2位
│   └── cd/                # 哈希3-4位  
│       └── abcdef123...webp  # 完整哈希值.webp
```

**存储流程**:
1. 下载原始图片
2. Pillow转WebP（质量可配置）
3. 计算SHA256哈希
4. 写入分片目录
5. 更新数据库引用

## 测试

```bash
# 运行所有测试
./venv/bin/python -m pytest tests/

# 测试特定适配器
./venv/bin/python -m pytest tests/test_adapter.py -k bilibili

# 测试API
./venv/bin/python -m pytest tests/test_api.py
```

## 开发文档

- [架构设计](docs/ARCHITECTURE.md) - 完整的系统架构、组件说明、适配器模式
- [API文档](docs/API.md) - 详细的API接口说明
- [数据库设计](docs/DATABASE.md) - 数据模型和索引策略
- [工作流程](docs/WORKFLOWS.md) - 内容处理流程和状态机
- [B站适配器](docs/BILIBILI_API.md) - B站平台解析实现
- [Twitter适配器](docs/TWITTER.md) - Twitter平台解析实现

## 技术栈

- **后端**: FastAPI + SQLAlchemy + aiosqlite
- **任务队列**: SQLite Task表
- **数据库**: SQLite（WAL模式）
- **存储**: 本地文件系统
- **图片处理**: Pillow（WebP转码）
- **日志**: Loguru
- **Bot**: python-telegram-bot

## 路线图

详见 [TODO.md](TODO.md)

当前重点：
- [x] M0: 基础架构（轻量化完成）
- [x] M1: 收藏入口与去重
- [x] M2: 解析流水线（Bilibili/Twitter适配器）
- [x] M3: 媒体存储与转码
- [ ] M4: 分享卡片与分发规则
- [ ] M5: Telegram Bot完善
- [ ] M6: Web管理端
- [ ] M7: Flutter移动端
- [ ] M8: AI摘要增强
- [ ] M9: 运维与安全
- [ ] M10: 测试覆盖

## 贡献指南

欢迎提交Issue和Pull Request！

## 许可证

MIT License
