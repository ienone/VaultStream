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
└── utils.py           # 解耦的工具函数 (URL规范化, 文本格式化)
docs/                  # 详细文档
static/                # 前端测试页面 (Material 3)
```

## 使用方法

### 1. 启动服务

```bash
./install.sh
cp .env.example .env  # 配置 TELEGRAM_BOT_TOKEN 等
./start.sh
```

### 1.1 （可选）启用私有归档媒体处理（图片→WebP→存储）

该功能仅作用于私有归档（`Content.raw_metadata.archive`），不会进入对外分享卡片字段。

- 本地存储（默认）
  - `.env`：设置 `STORAGE_BACKEND=local`、`STORAGE_LOCAL_ROOT=data/storage`
- MinIO/S3
  - 安装依赖：`pip install -r requirements.txt`（包含 `boto3`）
  - `.env`：设置 `STORAGE_BACKEND=s3`，并配置 `STORAGE_S3_ENDPOINT/BUCKET/ACCESS_KEY/SECRET_KEY`

MinIO（Docker）快速启动：

- `docker compose up -d minio`
- Console: `http://localhost:9001`（默认账号密码 `minioadmin/minioadmin`）
- S3 endpoint: `http://localhost:9000`

注意：

- 归档媒体存储会把结果写回 `Content.raw_metadata.archive`（私有）；不会影响对外分享卡片。
- `STORAGE_PUBLIC_BASE_URL` 只负责“把 key 映射成 URL”的字符串拼接；是否可匿名访问取决于你是否把 bucket 做成公开、或通过网关/鉴权访问。

MinIO 介入点（什么时候会写入对象存储）：

- Worker 在“适配器解析成功”后、写入 `Content.raw_metadata` 之前触发媒体处理：下载图片 → 转 WebP → 写入 Storage → 回写 `raw_metadata.archive.images[].stored_*`。
- 如果单张图片处理失败，默认会记录 warning 并继续处理其它图片，不会让整条内容解析失败。
- 如果你需要“补处理/重试失败图片”：重新入队同一条内容的 `parse` 任务时，worker 会在内容已是 `PULLED` 的情况下检测是否存在未处理图片（`stored_key` 为空），若存在则仅补处理媒体（不重新解析）。

MinIO bucket：

- 当 `STORAGE_BACKEND=s3` 时，系统会在首次写入前自动确保 bucket 存在（不存在则创建）。
- 归档图片默认以内容寻址（sha256）写入，例如：`vaultstream/blobs/sha256/ab/cd/<sha>.webp`。

启用开关：

- `.env`：设置 `ENABLE_ARCHIVE_MEDIA_PROCESSING=True`
- 可选调参：`ARCHIVE_IMAGE_WEBP_QUALITY`、`ARCHIVE_IMAGE_MAX_COUNT`

健康检查：

```bash
curl http://localhost:8000/health
```

### 1.2 导出某条内容为 Markdown（图片链接指向 MinIO WebP）

导出脚本会读取 `Content.raw_metadata.archive`，输出 Markdown 文件；可选补跑“缺失图片处理”。

1) 建议配置（用于把 stored_key 映射成可访问 URL）：

- `.env`：设置 `STORAGE_PUBLIC_BASE_URL=http://127.0.0.1:9000`

说明：这只会影响导出出来的 URL 字符串。MinIO 默认 bucket 通常是私有的，所以直接访问 `http://127.0.0.1:9000/<bucket>/<key>` 可能会 403。

两种可用方式（二选一）：

- 方式 A：把 bucket 设置为可匿名读取（开发环境最省事），这样 `9000/<bucket>/<key>` 能直接打开。
- 方式 B：保持 bucket 私有，启用 presigned URL（导出的链接会更长但可直接访问）：
  - `.env`：设置 `STORAGE_S3_PRESIGN_URLS=True`，可选 `STORAGE_S3_PRESIGN_EXPIRES=3600`
  - 此时可以不设置 `STORAGE_PUBLIC_BASE_URL`，系统会生成带签名的临时访问 URL。
  - 优先级：只要启用了 `STORAGE_S3_PRESIGN_URLS=True`，系统会优先生成 presigned URL（即使你同时配置了 `STORAGE_PUBLIC_BASE_URL`）。

2) 导出：

```bash
./venv/bin/python tests/export_markdown.py --content-id 6 --out exports/content_6.md
```

3) 导出前补处理缺失图片（推荐）：

```bash
./venv/bin/python tests/export_markdown.py --content-id 6 --out exports/content_6.md --process-missing-images --max-images 100
```

测试脚本目录：

- `tests/test_adapter.py`：离线 fixture 测试、适配器解析测试等
- `tests/export_markdown.py`：按 content_id 导出 Markdown（可选补处理缺失图片）


### 2. 提交分享

- Web 界面: 访问 `http://localhost:8000`。支持直接输入 BV/av/cv 号。
- API 提交:

```bash
curl -X POST http://localhost:8000/api/v1/shares \
  -H "Content-Type: application/json" \
  -d '{"url": "BV1xx411c7XD", "tags": ["技术", "教程"]}'
```

### 升级 / 迁移数据库

当代码包含数据模型变更（例如新增 `canonical_url` 或解析失败相关字段）时，请先运行迁移脚本：

```bash
./venv/bin/python migrate_db.py
```

该脚本会尝试幂等地为现有数据库添加缺失的列和索引（包括 `failure_count`、`last_error*` 等）。

### 回归测试示例（简要）

1) 新内容首次入库：

```bash
curl -sS -X POST 'http://127.0.0.1:8000/api/v1/shares' \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://www.bilibili.com/video/BV1newtest123","tags":["regress-new"],"source":"cli-test"}'
```

2) 已存在未解析内容再次提交（合并 tags 并重新入队；若解析失败会写入 `failure_count` / `last_error`）：

```bash
curl -sS -X POST 'http://127.0.0.1:8000/api/v1/shares' \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://www.bilibili.com/video/BV1newtest123","tags":["repeat-tag"],"source":"cli-repeat"}'
```

3) 已解析成功内容再次提交（仅合并 tags，不重复入队）：

```bash
curl -sS -X POST 'http://127.0.0.1:8000/api/v1/shares' \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://www.bilibili.com/video/BV198icBEErQ","tags":["post-pulled-test"],"source":"cli-pulled"}'
```

查看内容详情以观察 `status` 与失败信息：

```bash
curl -sS http://127.0.0.1:8000/api/v1/contents/3
```

### 3. Bot 交互

- `/get [tag]` - 获取并推送一条内容到频道。
- `/status` - 查看系统状态。

## 📚 详细文档

### 核心文档
- **[架构设计](docs/ARCHITECTURE.md)** - 完整的系统架构、组件说明、MinIO集成
- **[工作流程](docs/WORKFLOWS.md)** - 详细的流程图、序列图、故障排查
- **[优化总结](docs/OPTIMIZATION.md)** - 性能优化说明和效果对比

### 开发文档
- [设计思路](docs/DESIGN.md) - 项目设计理念和目标
- [数据库结构](docs/DATABASE.md) - 数据模型和表结构
- [API 接口契约](docs/API.md) - API接口说明
- [B站 API 对接](docs/BILIBILI_API.md) - B站适配器实现细节

### 其他
- [开发待办清单](TODO.md) - 功能规划和进度跟踪