# VaultStream

![Python](https://img.shields.io/badge/Python-3.11%2B-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.10%2B-blue)
![License](https://img.shields.io/badge/License-MIT-green)

私有内容存档与分发系统。从多个平台采集内容，本地化存储，按规则自动推送到 Telegram / QQ 等渠道。

---

## 功能概览

**内容采集**
- 支持 Bilibili、Twitter/X、小红书、知乎、微博，以及任意网页（通用适配器 + LLM 提取）
- 自动解析标题、正文、作者、标签、媒体文件
- 图片自动转码 WebP，视频/GIF 支持 ffmpeg 处理

**存档管理**
- SQLite 本地存储，FTS5 全文检索 + 标签筛选
- 内容状态管理（待解析 / 成功 / 失败 / 已归档）
- NSFW 标记与内容审批流

**自动分发**
- 基于规则的内容推送（按平台、标签匹配）
- 支持 Telegram Channel/Group、QQ（Napcat/OneBot 11）
- 推送去重、失败重试、优先级排序、排期投递

**多端管理**
- Flutter Web / Desktop / Mobile 客户端
- 响应式布局，Material 3 主题
- 收藏浏览、审批面板、仪表板、分发规则配置

---

## 部署

### Docker（推荐）

```bash
git clone https://github.com/ienone/VaultStream.git
cd VaultStream/backend
cp .env.example .env   # 编辑配置
docker compose up -d
```

生产环境 `.env` 必须配置：

```ini
APP_ENV=prod
DEBUG=False
API_TOKEN=<你的密钥>
CORS_ALLOWED_ORIGINS=https://your-domain.com
```

### 前端构建

在本地构建 Flutter Web 静态文件，部署到服务器由 Nginx 托管：

```bash
cd frontend
flutter pub get
dart run build_runner build
flutter build web --release
# 产物在 build/web/，上传到服务器即可
```

---

## 使用方式

1. 访问前端页面，通过界面添加内容链接、管理标签、浏览存档
2. 在前端「分发规则」页面配置推送目标和匹配条件，内容解析成功后自动推送
3. （可选）启动 Telegram Bot，直接向 Bot 发送链接即可入库：
   ```bash
   # Docker 内
   docker exec vaultstream python -m app.bot
   # 或手动部署
   .venv/bin/python -m app.bot
   ```

API 文档：启动后访问 http://localhost:8000/docs

---

## 项目结构

```
VaultStream/
├── backend/
│   ├── app/
│   │   ├── adapters/        # 平台解析器（bilibili, twitter, zhihu 等）
│   │   ├── routers/         # API 路由
│   │   ├── services/        # 业务逻辑
│   │   ├── repositories/    # 数据访问层
│   │   ├── distribution/    # 分发引擎 + 队列 Worker
│   │   ├── worker/          # 后台任务处理
│   │   ├── bot/             # Telegram Bot
│   │   ├── push/            # 推送服务（Telegram / Napcat）
│   │   ├── media/           # 媒体下载与转码
│   │   ├── core/            # 配置、数据库、日志、存储、事件总线
│   │   ├── models.py        # ORM 模型
│   │   ├── schemas.py       # 请求/响应 Schema
│   │   └── main.py          # FastAPI 入口
│   ├── data/                # SQLite 数据库 + 媒体文件
│   ├── migrations/          # 数据库迁移
│   ├── systemd/             # Systemd 服务配置
│   ├── Dockerfile
│   └── docker-compose.yml
├── frontend/                # Flutter 客户端
│   └── lib/features/        # 收藏、审批、仪表板、设置
└── docs/                    # API、架构、适配器文档
```

---

## Roadmap

以下功能在计划中，尚未实现：

- **RSS/Atom 订阅** — 支持 RSS 源自动抓取，全文入库，生成摘要
- **多源自动同步** — 绑定平台账号，自动同步收藏夹和关注更新
- **AI Agent 巡逻** — 基于用户偏好自动发现高价值内容，判断是否存档/推送
- **RAG 语义检索** — 对存档内容进行向量化，支持自然语言问答
- **Telegram 群组深度集成** — 全量存档群内链接，或由 LLM 筛选高价值内容

---


## 许可证

MIT License
