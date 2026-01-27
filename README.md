# VaultStream - 跨平台内容收藏 & 分享系统

![Python](https://img.shields.io/badge/Python-3.10%2B-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.10%2B-blue)
![License](https://img.shields.io/badge/License-MIT-green)

VaultStream 是一个私有内容存档与合规分享的完整解决方案。通过适配器系统支持多平台（B站、Twitter、小红书等）内容采集，提供本地化存储、智能分发，确保私有数据与公开分享严格隔离。

## 🎯 核心特性

### 私有存档 (Private Archive)
- 📥 多平台采集: B站视频、Twitter/X、小红书、知乎、微博等
- 🎬 完整媒体存档: 图片、视频、文本等本地化存储
- 🔍 智能检索: FTS5 全文搜索 + 标签多维筛选
- 🏷️ 灵活标记: 自定义标签、NSFW 标记、收藏备注

### 合规分享 (Compliance Share)
- 🚀 智能分发: 基于规则的自动推送（Telegram、QQ 等）
- 🔐 严格隔离: 分享卡片仅包含标题、摘要、媒体，不泄露原始数据
- 📋 审批流: 手动审批或自动分流，NSFW 内容硬拦截
- 📊 推送审计: 完整的推送历史追踪，支持重推、撤回

### 系统架构
- 🪶 轻量化: SQLite + 本地存储，~200MB 内存占用，无需 Docker/容器
- ⚡ 高效能: SQLite WAL 模式，支持并发读写
- 🔄 可观测: 结构化日志、请求追踪、任务队列监控

## 📋 项目里程碑

### ✅ 已完成 (M0-M5)

| 里程碑 | 说明 | 状态 |
|-------|------|------|
| M0 | 项目基础与轻量化架构 | ✅ 完成 |
| M1 | 收藏入口与去重模型 | ✅ 完成 |
| M2 | 解析流水线与 Adapter 体系 | ✅ 完成 (B站、Twitter、小红书、知乎、微博) |
| M3 | 私有存档与媒体存储 | ✅ 完成 (WebP 转码、FTS5 搜索、代理 API) |
| M4 | 分发规则与审批流 | ✅ 完成 (分发引擎、推送历史、NSFW 分流) |
| M5 | Telegram Bot 实现 | ✅ 完成 (命令系统、Media Group、自动推送) |

### 🚧 进行中 (M6+)

| 里程碑 | 说明 | 进度 |
|-------|------|------|
| M6 | Flutter 多端客户端 (Web/Desktop/Mobile) | 🚧 20% |
| M7 | 移动端深度集成 (分享采集) | 🚧 0% |
| M8 | AI 摘要与语义检索 | 🚧 0% |
| M9 | 运维、安全、合规 | 🚧 0% |
| M10 | 完整测试覆盖 | 🚧 10% |

## 📁 项目结构

```
VaultStream/
├── backend/                          # Python FastAPI 后端
│   ├── app/                          # 应用主体
│   │   ├── adapters/                 # 平台解析适配器
│   │   │   ├── base.py              # 适配器基类
│   │   │   ├── bilibili.py          # B站解析器
│   │   │   ├── twitter_fx.py        # Twitter/X 解析器
│   │   │   ├── xiaohongshu.py       # 小红书解析器
│   │   │   ├── zhihu.py             # 知乎解析器
│   │   │   ├── weibo.py             # 微博解析器
│   │   │   ├── errors.py            # 异常定义
│   │   │   ├── utils/               # 适配器工具函数
│   │   │   ├── bilibili_parser/     # B站解析工具包
│   │   │   ├── weibo_parser/        # 微博解析工具包
│   │   │   ├── xiaohongshu_parser/  # 小红书解析工具包
│   │   │   └── zhihu_parser/        # 知乎解析工具包
│   │   ├── routers/                 # API 路由
│   │   │   ├── auth.py              # 认证路由
│   │   │   ├── contents.py          # 内容管理路由
│   │   │   ├── distribution.py      # 分发规则路由
│   │   │   ├── media.py             # 媒体相关路由
│   │   │   ├── shares.py            # 分享入口路由
│   │   │   ├── stats.py             # 统计信息路由
│   │   │   └── tags.py              # 标签管理路由
│   │   ├── repositories/            # 数据仓库层 (DAL)
│   │   │   ├── content_repository.py
│   │   │   ├── distribution_repository.py
│   │   │   ├── media_repository.py
│   │   │   └── tag_repository.py
│   │   ├── services/                # 业务逻辑服务层
│   │   │   ├── auth_service.py
│   │   │   ├── content_service.py
│   │   │   ├── distribution_service.py
│   │   │   ├── media_service.py
│   │   │   └── push_service.py
│   │   ├── worker/                  # 异步任务处理
│   │   │   ├── __init__.py
│   │   │   ├── task_handler.py      # 任务处理器
│   │   │   └── queue.py             # 队列管理
│   │   ├── bot/                     # Telegram Bot 逻辑（可选）
│   │   │   └── telegram_bot.py
│   │   ├── telegram/                # Telegram 推送
│   │   │   ├── client.py
│   │   │   └── handlers.py
│   │   ├── push/                    # 推送引擎
│   │   │   ├── __init__.py
│   │   │   └── dispatcher.py
│   │   ├── distribution/            # 分发相关
│   │   │   ├── __init__.py
│   │   │   └── rules_engine.py
│   │   ├── media/                   # 媒体处理
│   │   │   ├── __init__.py
│   │   │   ├── processor.py
│   │   │   └── storage.py
│   │   ├── core/                    # 核心组件
│   │   │   ├── __init__.py
│   │   │   ├── database.py          # SQLite 初始化
│   │   │   ├── config.py            # 配置管理
│   │   │   └── logger.py            # 日志配置
│   │   ├── utils/                   # 工具函数
│   │   │   ├── __init__.py
│   │   │   ├── url_utils.py
│   │   │   ├── crypto.py
│   │   │   └── validators.py
│   │   ├── models.py                # SQLAlchemy ORM 数据模型
│   │   ├── schemas.py               # Pydantic 请求/响应 schema
│   │   ├── main.py                  # FastAPI 应用入口
│   │   └── README.md                # 后端模块说明
│   ├── data/                        # 运行时数据目录 (生成)
│   │   ├── vaultstream.db          # SQLite 数据库
│   │   └── media/                  # 媒体文件存储 (SHA256 寻址)
│   ├── logs/                        # 日志目录 (生成)
│   │   ├── vaultstream.log        # 文本日志
│   │   └── vaultstream.json.log   # JSON 结构化日志
│   ├── tests/                       # 测试套件
│   │   ├── conftest.py             # pytest 配置
│   │   ├── test_adapters/          # 适配器单元测试
│   │   ├── test_api/               # API 集成测试
│   │   ├── export_markdown.py      # 导出工具
│   │   └── check_tags.py           # 标签检查工具
│   ├── migrations/                  # 数据库迁移 (预留)
│   ├── scripts/                     # 部署和维护脚本
│   ├── systemd/                     # Systemd service 配置
│   ├── tools/                       # 杂项工具
│   ├── static/                      # 静态文件
│   ├── requirements.txt             # Python 依赖
│   ├── pytest.ini                   # pytest 配置
│   ├── install.sh                   # Linux 安装脚本
│   ├── install.bat                  # Windows 安装脚本
│   ├── start.sh                     # Linux 启动脚本
│   ├── start.ps1                    # PowerShell 启动脚本
│   ├── start.bat                    # Windows 启动脚本
│   └── .env.example                 # 环境变量示例
│
├── frontend/                        # Flutter 客户端 (多端支持)
│   ├── lib/
│   │   ├── main.dart                # 应用入口
│   │   ├── core/                    # 核心模块
│   │   │   ├── config/              # 应用配置
│   │   │   ├── network/             # 网络层
│   │   │   │   ├── api_client.dart  # API 客户端
│   │   │   │   └── interceptors.dart # 拦截器
│   │   │   ├── providers/           # 全局 Riverpod providers
│   │   │   ├── services/            # 本地存储等服务
│   │   │   ├── utils/               # 工具函数
│   │   │   └── widgets/             # 通用 Widget
│   │   ├── features/                # 功能模块 (Clean Architecture)
│   │   │   ├── collection/          # 收藏中心 (M3 集成)
│   │   │   │   ├── data/
│   │   │   │   ├── domain/
│   │   │   │   └── presentation/
│   │   │   ├── review/              # 审批面板 (M4 集成)
│   │   │   │   ├── data/
│   │   │   │   ├── domain/
│   │   │   │   └── presentation/
│   │   │   ├── dashboard/           # 仪表板 (监控)
│   │   │   │   └── presentation/
│   │   │   └── settings/            # 设置页面
│   │   │       └── presentation/
│   │   ├── routing/                 # go_router 路由配置
│   │   ├── layout/                  # 响应式布局组件
│   │   └── theme/                   # 主题配置 (Material 3)
│   ├── test/                        # Widget 测试
│   ├── web/                         # Web 构建输出
│   ├── android/                     # Android 原生配置
│   ├── linux/                       # Linux 桌面构建配置
│   ├── analysis_options.yaml        # Dart 分析规则
│   ├── pubspec.yaml                 # Flutter 依赖配置
│   ├── pubspec.lock                 # 依赖锁定文件
│   ├── README.md                    # 前端开发指南
│   └── .metadata                    # Flutter 元数据
│
├── docs/                            # 项目文档
│   ├── API.md                       # REST API 接口文档
│   ├── ARCHITECTURE.md              # 系统架构设计
│   ├── DATABASE.md                  # 数据库设计与索引
│   ├── WORKFLOWS.md                 # 核心工作流程
│   ├── M4_DISTRIBUTION.md           # 分发规则与审批流
│   ├── BILIBILI_ADAPTER.md          # B站适配器实现
│   ├── TWITTER_ADAPTER.md           # Twitter 适配器实现
│   ├── XIAOHONGSHU_ADAPTER.md       # 小红书适配器
│   ├── ZHIHU_ADAPTER.md             # 知乎适配器
│   └── WEIBO_ADAPTER.md             # 微博适配器
│
├── data/                            # 项目级数据目录
│   └── media/                       # 共享媒体存储
│
├── AGENTS.md                        # 项目规范与命令
├── COMPLETE.md                      # 已完成项目总结 (M0-M5)
├── TASKS.md                         # 待完成任务 (M6-M10)
├── README.md                        # 项目总览 (本文件)
├── SETUP_GUIDE.md                   # 完整安装指南
├── TODO.md                          # 高层规划 (原始需求)
└── 设计思路.md                      # 设计文档
```

**核心目录说明**:
- `backend/data/` - 本地数据存储（SQLite 数据库、媒体文件）
- `backend/logs/` - 运行日志（自动创建）
- `frontend/lib/core/` - 核心模块：网络、状态、服务
- `frontend/lib/features/` - 功能模块：集合、审批、仪表板、设置
- `docs/` - 详细技术文档

## 🚀 快速开始

### 环境要求

| 组件 | 版本要求 | 说明 |
|------|----------|------|
| Python | 3.10+ | 后端运行环境 |
| Flutter | 3.10+ | 前端开发环境 |
| SQLite | 3.35+ | 数据库 (通常预装) |
| Node.js | 16+ | (可选) 前端构建工具 |

### 安装 & 启动

#### Linux / macOS

```bash
# 1. 克隆项目
git clone https://github.com/ienone/VaultStream.git
cd VaultStream

# 2. 安装后端依赖
cd backend
bash install.sh   # 交互式安装，可选择虚拟环境或系统 Python

# 3. 启动后端
bash start.sh

# 4. (另一个终端) 安装前端依赖
cd frontend
flutter pub get
dart run build_runner build # 代码生成

# 5. 启动前端 (Web/Desktop/Mobile)
flutter run -d chrome        # Web 版本
# 或其他设备
```

#### Windows

```bash
# 1. 克隆项目
git clone https://github.com/ienone/VaultStream.git
cd VaultStream\backend

# 2. 安装后端依赖
install.bat                 # 创建虚拟环境

# 3. 启动后端
start.bat

# 4. (另一个 PowerShell) 安装前端依赖
cd ..\frontend
flutter pub get
dart run build_runner build

# 5. 启动前端
flutter run -d chrome      # Web 版本
```

### 首次使用

1. **配置环境变量**:
   ```bash
   cp backend/.env.example backend/.env
   # 编辑 .env，可选配置 (Telegram Bot):
   # - ENABLE_BOT=True (启用 Bot，默认 False)
   # - TELEGRAM_BOT_TOKEN (仅在 ENABLE_BOT=True 时需要)
   # - TELEGRAM_CHANNEL_ID (仅在 ENABLE_BOT=True 时需要)
   ```

2. **验证后端**:
   ```bash
   curl http://localhost:8000/health
   ```

3. **（可选）启动 Telegram Bot**:
   仅当需要 Bot 功能时，在 `.env` 中设置 `ENABLE_BOT=True` 并配置，然后：
   ```bash
   cd backend
   ./.venv/bin/python -m app.bot
   ```

4. **访问前端**:
   - 本地: http://localhost:8080 (Web 版本)
   - API 文档: http://localhost:8000/docs
   - 交互式 API: http://localhost:8000/redoc

## 📚 使用文档

### 后端 API 指南

```bash
# 1. 添加分享
curl -X POST http://localhost:8000/api/v1/shares \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://www.bilibili.com/video/BV1xx411c7mD",
    "tags": ["技术", "教程"],
    "note": "值得收藏",
    "is_nsfw": false
  }'

# 2. 查询内容
curl "http://localhost:8000/api/v1/contents?tag=技术&limit=10"

# 3. 获取详情
curl http://localhost:8000/api/v1/contents/123

# 4. Telegram Bot 推送
curl -X POST http://localhost:8000/api/v1/bot/get-content \
  -H "Content-Type: application/json" \
  -d '{
    "target_platform": "TG_CHANNEL_@example",
    "limit": 5
  }'
```

详细 API 文档见: [docs/API.md](docs/API.md)

### 前端开发指南

见: [frontend/README.md](frontend/README.md)

### 平台适配器

- [B站适配器](docs/BILIBILI_ADAPTER.md)
- [Twitter 适配器](docs/TWITTER_ADAPTER.md)
- [小红书适配器](docs/XIAOHONGSHU_ADAPTER.md)
- [知乎适配器](docs/ZHIHU_ADAPTER.md)
- [微博适配器](docs/WEIBO_ADAPTER.md)

## 🛠️ 开发

### 后端开发

```bash
# 运行测试
cd backend
.venv/bin/python -m pytest tests/

# 单个测试
.venv/bin/python -m pytest tests/test_adapter.py -k bilibili

# 代码格式化 (可选)
.venv/bin/python -m black app/
.venv/bin/python -m isort app/
```

### 前端开发

```bash
# 代码生成 (必须在修改 model/adapter 后执行)
cd frontend
dart run build_runner build

# 或监听变化自动生成
dart run build_runner watch

# 代码分析
flutter analyze

# 格式化
dart format lib/
```

### 数据库操作

```bash
# 导出内容为 Markdown
.venv/bin/python backend/tests/export_markdown.py \
  --content-id 6 \
  --out backend/exports/content_6.md \
  --process-missing-images

# 访问 SQLite 数据库
sqlite3 data/vaultstream.db
> SELECT COUNT(*) FROM contents;
```

## 📊 系统监控

### 日志查看

```bash
# 实时日志
tail -f logs/vaultstream.log

# JSON 日志 (用于日志聚合)
tail -f logs/vaultstream.json.log | jq .

# 错误过滤
grep ERROR logs/vaultstream.log
```

### 队列监控

访问 API 获取队列统计:

```bash
curl http://localhost:8000/api/v1/stats
```

响应:
```json
{
  "pending_count": 10,
  "processing_count": 2,
  "failed_count": 5,
  "total_contents": 156
}
```

### 系统健康检查

```bash
curl http://localhost:8000/health
```

## 🔐 安全考虑

- ✅ 私有存档隔离: `contents.raw_metadata.archive` 仅内部使用
- ✅ 分享卡片独立: 分享数据结构严格分离，不含原始内容
- ✅ NSFW 分流: 不合规内容硬拦截，不送往公开分享
- ✅ 推送追踪: `pushed_records` 确保推过不再推
- ✅ 敏感信息保护: Cookie/Token 加密存储、日志脱敏

详见: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)


## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！

1. Fork 项目
2. 创建特性分支: `git checkout -b feature/AmazingFeature`
3. 提交更改: `git commit -m 'Add AmazingFeature'`
4. 推送到分支: `git push origin feature/AmazingFeature`
5. 提交 Pull Request

### 代码规范

- Python: 遵循 PEP 8，使用 type hints
- Dart: 遵循 Effective Dart，使用 freezed + json_serializable
- 提交信息: 清晰描述，英文或中文均可

## 📝 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 🙏 致谢

感谢所有为这个项目做出贡献的开发者！

## 📧 联系方式

- 问题报告: [GitHub Issues](https://github.com/ienone/VaultStream/issues)
- 功能建议: [GitHub Discussions](https://github.com/ienone/VaultStream/discussions)
- 邮件: your-email@example.com

---

最后更新: 2026年1月27日
