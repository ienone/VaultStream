# VaultStream 数据库文档

## 文档状态

active

## 文档职责

本文是数据库当前实现的入口，不逐字段复制全部 ORM。领域字段、关系和一致性要求拆分到下列文档：

- `database/content-search.md`：内容、来源、发现关联、语义索引和 FTS。
- `database/automation-delivery.md`：任务、设置、分发队列、推送和 Bot。
- `database/agent.md`：Agent 会话、运行、工具、确认和上下文摘要。

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
| 内容与媒体 | `contents`、`content_sources`、`discovery_sources`、`content_discovery_links`、`media_assets`、`media_variants` |
| 搜索 | `content_embeddings`、运行期 `contents_fts` |
| 系统与任务 | `tasks`、`system_settings` |
| 分发 | `distribution_rules`、`distribution_targets`、`content_queue_items`、`pushed_records` |
| Bot | `bot_configs`、`bot_chats`、`bot_runtime` |
| Agent | `agent_sessions`、`agent_messages`、`agent_runs`、`agent_tool_calls`、`agent_confirmations`、`agent_context_summaries` |

## 初始化与升级边界

应用启动通过 SQLAlchemy metadata 创建 ORM 表，并在数据库初始化代码中处理当前运行所需结构。历史迁移脚本不是新环境的基线，也不应在本文中列为手动必跑步骤。

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

当前已知 schema gate 与文档漂移问题见 `../issues/backend-schema-gate-database-doc-drift.md`。
