# VaultStream 数据库文档

## 文档状态

active

## 文档职责

本文是数据库当前实现的入口，不逐字段复制全部 ORM。领域字段、关系和一致性要求拆分到下列文档：

- `database/content-search.md`：内容、来源、发现关联、语义索引和 FTS。
- `database/automation-delivery.md`：任务、设置、分发队列、推送和 Bot。
- `database/agent.md`：Agent 会话、运行、工具、确认和上下文摘要。
- `database/content-search.md`：同时记录跨内容知识事件关系。

## 事实优先级

1. `backend/app/models/` 中的当前 ORM 模型。
2. `backend/app/core/database.py` 创建的运行期 SQLite 结构，例如 FTS5、触发器和兼容补列。
3. 可重复执行的 schema/完整性检查结果。
4. 本文档。
5. 历史数据库和旧迁移记录。

文档与代码不一致时必须更新文档或创建 issue，不能让调用方兼容多个猜测结构。

## 当前领域

| 领域 | 表或结构 |
| :--- | :--- |
| 内容与媒体 | `contents`、`content_sources`、`discovery_sources`、`content_discovery_links`、`media_assets`、`media_variants`、`media_bookmarks` |
| 搜索 | `content_embeddings`、运行期 `contents_fts` |
| 系统、任务与消息 | `tasks`、`system_settings`、`background_task_runs`、`notification_messages` |
| 分发 | `distribution_rules`、`distribution_targets`、`content_queue_items`、`pushed_records` |
| Bot | `bot_configs`、`bot_chats`、`bot_runtime` |
| Agent | `agent_sessions`、`agent_messages`、`agent_runs`、`agent_tool_calls`、`agent_confirmations`、`agent_context_summaries` |
| 知识事件 | `knowledge_events`、`knowledge_event_members` |
| 运行期门禁 | `schema_metadata`、FTS5 表与触发器、兼容补列及关键索引 |

## 初始化与升级边界

应用启动通过 SQLAlchemy metadata 创建 ORM 表，并在数据库初始化代码中处理当前运行所需结构。历史迁移脚本不是新环境的基线，也不应在本文中列为手动必跑步骤。

`ensure_schema_metadata()` 只保证运行期元数据表存在，不代表某个迁移已完成。历史迁移必须在自身结构变更成功后用 `record_schema_version()` 显式记录对应版本；该写入不会把较新的库降级。当前启动流程完成 ORM 建表、兼容补齐和 FTS 初始化后，先检查完整性、外键、关键表/列/索引及 FTS，再决定是否把版本推进到当前值。版本号本身不能替代结构检查。

升级早期数据库前必须：

- 备份数据库及配套媒体。
- 对比目标 ORM 与实际 schema。
- 为该版本建立独立、可验证的迁移计划。
- 执行完整性、外键、索引和核心查询验证。

## 验证

最低验证包括：

- `PRAGMA integrity_check`。
- `PRAGMA foreign_key_check`。
- ORM 表、列、索引与实际 SQLite schema 对比。
- `contents` 与 FTS 索引的一致性。
- 分发队列领取、重试和唯一性查询计划。
- Agent context summary 等外键列的索引检查。
- `schema_metadata.schema_version` 与当前要求的版本比较。

当前 schema gate 版本为 33，并以 manifest 检查内容编辑/语义索引、任务账本、消息盒子、知识事件、播放书签和 Agent 上下文摘要的关键结构。仓库实验数据库仍需同时通过完整性、外键与 FTS 一致性检查。原先由启动过程自我提升版本的问题已[归档](../issues/archive/backend-schema-gate-database-doc-drift.md)。
