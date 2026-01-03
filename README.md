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

健康检查：

```bash
curl http://localhost:8000/health
```

### 2. 提交分享

- Web 界面: 访问 `http://localhost:8000`。支持直接输入 BV/av/cv 号。
- API 提交:

```bash
curl -X POST http://localhost:8000/api/v1/shares \
  -H "Content-Type: application/json" \
  -d '{"url": "BV1xx411c7XD", "tags": ["技术", "教程"]}'
```

### 3. Bot 交互

- `/get [tag]` - 获取并推送一条内容到频道。
- `/status` - 查看系统状态。

## 📚 详细文档

- [设计思路](docs/DESIGN.md)
- [数据库结构](docs/DATABASE.md)
- [API 接口契约](docs/API.md)
- [开发待办清单](docs/TODO.md)