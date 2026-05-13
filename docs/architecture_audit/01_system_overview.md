# 01 — 系统全貌

## 1.1 模块地图

```
backend/app/
├── main.py                    # FastAPI 应用 + lifespan 编排
├── constants.py
│
├── core/                      # 基础设施层
│   ├── config.py              # Pydantic BaseSettings 单例 `settings`
│   ├── database.py            # init_db(), get_db()
│   ├── db_adapter.py          # SQLAlchemy async engine + AsyncSessionLocal
│   ├── events.py              # EventBus（SSE + SQLite outbox）
│   ├── queue.py               # task_queue 单例
│   ├── queue_adapter.py       # SQLite 任务队列实现
│   ├── llm_factory.py         # LangChain LLM 工厂
│   ├── crawler_config.py      # 爬虫配置
│   └── dependencies.py        # FastAPI 依赖注入（auth token）
│
├── models/                    # SQLAlchemy ORM 模型
│   ├── base.py                # DeclarativeBase + 所有枚举
│   ├── content.py             # Content, ContentSource, DiscoverySource, ContentDiscoveryLink
│   ├── distribution.py        # DistributionRule, DistributionTarget
│   ├── bot.py                 # BotConfig, BotChat, BotRuntime
│   ├── system.py              # Task, SystemSetting, PushedRecord, ContentQueueItem
│   └── search.py              # ContentEmbedding（多分块）
│
├── repositories/              # 数据访问层（Repository Pattern）
│   ├── content_repository.py
│   ├── distribution_repository.py
│   ├── system_repository.py
│   └── bot_repository.py
│
├── services/                  # 业务逻辑层
│   ├── settings_service.py           # 配置读写 + _SETTINGS_CACHE
│   ├── content_service.py            # 内容 CRUD + 分发触发
│   ├── content_summary_service.py    # AI 摘要 + 语义分块
│   ├── embedding_service.py          # 向量索引 + 混合搜索
│   ├── content_presenter.py          # 内容格式化（推送用）
│   ├── distribution/
│   │   ├── engine.py                 # 规则匹配 + 自动审批
│   │   ├── scheduler.py              # 分发队列入队
│   │   └── decision.py              # 条件判断函数
│   ├── distribution_rule_service.py
│   ├── dashboard_service.py
│   ├── patrol_service.py             # Discovery AI 评分
│   ├── telegram_bot_service.py       # Bot 进程管理
│   ├── telegram_sync.py
│   ├── background_task_leader.py     # 单主进程选举（PID 文件）
│   ├── bot_config_runtime.py
│   ├── browser_auth_service.py       # QR 登录 + Cookie 持久化
│   └── agent/
│       ├── service.py                # AI Agent 入口
│       └── tool_registry.py          # 工具注册表
│
├── tasks/                     # 后台任务层
│   ├── runner.py              # TaskWorker（消费 task_queue）
│   ├── parsing.py             # ContentParser（解析流水线神类，848 行）
│   ├── distribution_worker.py # DistributionQueueWorker（推送分发，609 行）
│   ├── discovery_sync.py      # DiscoverySyncTask（RSS/Telegram 同步）
│   ├── favorites_sync.py      # FavoritesSyncTask（收藏夹同步）
│   ├── discovery_cleanup.py   # 过期 Discovery 清理
│   └── maintenance.py         # 其他维护任务
│
├── adapters/                  # 平台适配层
│   ├── base.py                # BaseAdapter 协议
│   ├── bilibili.py / bilibili_parser/
│   ├── zhihu.py (945 行)      # 知乎适配器（最长单文件）
│   ├── weibo.py / weibo_parser/
│   ├── xiaohongshu.py / xiaohongshu_parser/
│   ├── twitter.py
│   ├── rss.py (646 行)
│   ├── telegram.py
│   ├── universal_adapter.py
│   ├── storage/manager.py     # 存储后端（本地 FS / S3）
│   ├── browser/manager.py     # Playwright 浏览器会话管理
│   ├── favorites/             # 收藏夹抓取器（Twitter / XHS / Zhihu）
│   ├── discovery/             # 发现源（RSS / Telegram Channel）
│   └── utils/
│       ├── content_agent.py   # LLM 内容提取（936 行）
│       ├── tiered_fetcher.py  # 分级 HTTP 抓取策略
│       ├── archive_builder.py # 存档构建
│       ├── anti_risk.py       # 反风控工具
│       └── cookie_utils.py    # Cookie 解析工具
│
├── routers/                   # HTTP 路由层（FastAPI）
├── schemas/                   # Pydantic I/O 模型
├── media/                     # 媒体处理（下载/转码/颜色提取）
├── push/                      # 推送后端（Telegram / Napcat）
├── bot/                       # Telegram Bot 子进程
└── utils/                     # 通用工具（标签/URL/文本格式化）
```

---

## 1.2 系统链路清单

| # | 链路名称 | 触发方式 | 主要参与方 |
|---|---|---|---|
| 1 | **内容采集** | `POST /contents/share` | ContentService → TaskQueue → ContentParser |
| 2 | **分发推送** | 内容审批 / 自动审批 | DistributionEngine → ContentQueueItem → PushService |
| 3 | **发现同步** | 定时 60s | DiscoverySyncTask → PatrolService (AI 评分) |
| 4 | **收藏夹同步** | 定时 / 手动 | FavoritesSyncTask → ContentService |
| 5 | **语义搜索** | `GET /search` | EmbeddingService → RRF 融合 |
| 6 | **Bot 交互** | Telegram 消息 | Bot 子进程 → HTTP → Backend API |
| 7 | **配置管理** | `PUT /system/settings` | settings_service → DB + Cache + Settings 对象 |
| 8 | **AI Agent** | `POST /agent/run` / Bot `/ai` | AgentService → ToolRegistry → Tools |
| 9 | **浏览器认证** | `POST /auth/{platform}/qr-start` | BrowserAuthService → Playwright |
| 10 | **SSE 事件** | `GET /events` | EventBus → asyncio.Queue → SSE stream |

---

## 1.3 全局单例与模块级状态库存

| 变量 | 位置 | 类型 | 说明 | 风险 |
|---|---|---|---|---|
| `settings` | `core/config.py` | `Settings`（Pydantic） | 从 `.env` 加载，运行时被 `setattr` 修改 | 多线程不安全，源头不唯一 |
| `_SETTINGS_CACHE` | `services/settings_service.py` | `dict[str, Any]` | 无 TTL、无跨进程同步的内存缓存 | 多 worker 进程各自独立，更新不传播 |
| `task_queue` | `core/queue.py` | `TaskQueue` | SQLite 任务队列单例 | 无 |
| `event_bus` | `core/events.py` | `EventBus` 实例 | **但 `_subscribers` 等是类属性！** | 第二次实例化会共享状态 |
| `_REGISTRY` | `services/agent/service.py` | `AgentToolRegistry \| None` | 懒初始化，无锁保护 | 并发首次调用可能创建两个实例 |
| `background_task_leader` | `services/background_task_leader.py` | `BackgroundTaskLeader` | PID 文件选举单主进程 | Windows 上 PID 循环利用可能误判 |
| `AsyncSessionLocal` | `core/db_adapter.py` | SQLAlchemy `async_sessionmaker` | 全局 Session 工厂 | 无 |
| `_push_service_cache` | `tasks/distribution_worker.py` | `dict` | 推送服务懒初始化缓存 | `_get_bot()` 无锁，并发初始化竞争 |

---

## 1.4 数据库表清单

| 表名 | 对应模型 | 核心字段 |
|---|---|---|
| `contents` | `Content` | platform, canonical_url, status, review_status, discovery_state, rich_payload(JSON), context_data(JSON) |
| `content_sources` | `ContentSource` | content_id, raw_url, submitted_at |
| `discovery_sources` | `DiscoverySource` | kind, url, last_synced_at, enabled |
| `content_discovery_links` | `ContentDiscoveryLink` | content_id, discovery_source_id |
| `content_embeddings` | `ContentEmbedding` | content_id, chunk_index, embedding(JSON), text_hash, chunk_title |
| `distribution_rules` | `DistributionRule` | conditions(JSON), enabled, auto_approve |
| `distribution_targets` | `DistributionTarget` | rule_id, bot_chat_id, backfill_watermark |
| `content_queue_items` | `ContentQueueItem` | content_id, rule_id, bot_chat_id, status, locked_by, retry_count |
| `pushed_records` | `PushedRecord` | content_id, target_id, message_id |
| `bot_configs` | `BotConfig` | platform, token(加密存储) |
| `bot_chats` | `BotChat` | bot_config_id, chat_id, push_count |
| `bot_runtimes` | `BotRuntime` | config_id, pid, last_heartbeat_at |
| `system_settings` | `SystemSetting` | key, value（通用 KV 表，存 API Key / Cookie / 功能开关） |
| `tasks` | `Task` | content_id, status, priority, created_at |
| `system_events` | `SystemEvent` | event_type, payload(JSON)（SSE outbox） |
