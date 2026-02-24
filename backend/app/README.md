# VaultStream Backend Application Structure

本文档说明后端应用 (`backend/app/`) 的目录结构和模块职责。

## 目录概览


```
app/
├── core/               # 核心基础设施 (配置, 数据库, 日志, 存储)
├── utils/              # 通用工具函数 (URL, 文本处理)
├── media/              # 媒体处理模块 (下载, 提取, 转码)
├── push/               # 消息推送服务 (Telegram 等)
├── distribution/       # 内容自动分发引警
├── worker/             # 后台任务处理逻辑
├── bot/                # Telegram 交互机器人
├── adapters/           # 平台解析适配器 (Bilibili, Twitter 等)
├── routers/            # API 路由定义
├── schemas.py          # Pydantic 数据模型
├── models.py           # SQLAlchemy 数据库模型
└── main.py             # 应用入口
```

## 模块详情

### 1. `core/` (核心基础设施)
基础服务模块，被其他高层业务模块引用。
- config.py: 环境配置加载 (`settings`)
- database.py: 数据库连接管理 (`get_db`, `init_db`)
- logging.py: 全局日志配置 (`logger`)
- storage.py: 文件存储后端接口 (`Local`)
- queue.py: SQLite 任务队列接口

### 2. `worker/` (后台任务)
原 `worker.py` 已拆分，负责处理异步任务。
- task_processor.py: 任务调度主类 `TaskWorker`
- parser.py: 内容解析业务逻辑 `ContentParser`
- distributor.py: 分发业务逻辑 `ContentDistributor`

### 3. `bot/` (Telegram Bot)
原 `bot.py` 已拆分，负责交互式命令。
- main.py: Bot 生命周期管理
- commands.py: `/start`, `/get` 等命令处理
- callbacks.py: 按钮回调处理
- permissions.py: 用户权限管理

### 4. `distribution/` (自动分发)
- engine.py: 规则匹配引擎，决定内容是否分发
- queue_service.py: 事件驱动入队服务（`enqueue_content`）
- queue_worker.py: 队列消费 Worker（并发推送、重试与退避）

### 5. `media/` (媒体处理)
- processor.py: 媒体文件下载、WebP 转码
- extractor.py: 从元数据提取媒体 URL
- color.py: 图片主色调提取

### 6. `push/` (推送服务)
- base.py: 推送服务基类
- telegram.py: Telegram 渠道实现

## 开发指南

- 添加新路由: 在 `routers/` 新建文件，并在 `main.py` 注册。
- 修改Parser逻辑: 修改 `worker/parser.py` 并添加 `adapters/` 下的具体适配器。
- 修改Bot命令: 在 `bot/commands.py` 添加函数，并在 `bot/main.py` 注册。

## 引用规范

所有内部引用应使用绝对导入，例如：
```python
# 正确
from app.core.config import settings
from app.worker import worker

# 统一使用 app.* 绝对导入路径
```
