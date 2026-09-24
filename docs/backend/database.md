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
2. `backend/app/core/database.py` 中的 FTS5、触发器与 SSE 初始结构，以及 `backend/migrations/versions/` 中的后续增量迁移。
3. 可重复执行的 schema/完整性检查结果。
4. 本文档。

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
| 迁移与事件 | `alembic_version`、`realtime_events`、FTS5 表与触发器 |

## 初始化与升级边界

`init_db()` 对空库使用 SQLAlchemy `Base.metadata.create_all()` 创建当前 ORM 结构，补充 FTS/SSE 后执行 Alembic `stamp head`；已有 Alembic 库只执行 `upgrade head`。不保存重复的全量结构快照。`20260920_media_archive_items` 合并重复媒体索引；`20260920_single_facts` 收敛来源、Agent、队列、Bot、索引和同步结果的重复事实，保留关联 ID 并恢复 SQLite FTS 触发器。迁移连接在事务前关闭外键动作以避免 batch 重建级联删除，提交前执行外键完整性检查；常规连接仍开启外键。

当前历史数据库均为测试数据，不支持旧 `schema_metadata` 库的自动接管或历史数据转换。旧测试库须清空重建；应用不会自动清库，也不会对已有业务表执行 `create_all()` 或 `stamp head` 冒充升级。

新库由应用启动的 `init_db()` 初始化，也可运行 `scripts/check_database_schema.py --db 路径`。以下 Alembic 命令用于已初始化的库；在仓库根目录使用根虚拟环境，`SQLITE_DB_PATH` 选择目标库：

```sh
.venv/bin/python -m alembic -c backend/alembic.ini upgrade head
.venv/bin/python -m alembic -c backend/alembic.ini current
.venv/bin/python -m alembic -c backend/alembic.ini check
.venv/bin/python -m alembic -c backend/alembic.ini revision --autogenerate -m "变更说明"
```

修改模型后生成并审阅新 revision，再执行升级。SQLite 结构变更使用 Alembic batch；FTS/SSE 不属于 ORM 自动生成范围，变更时同步更新新库初始化定义及已有库的增量 revision。Docker 镜像包含同一配置与迁移目录。

## 验证

最低验证包括：

- `PRAGMA integrity_check`。
- `PRAGMA foreign_key_check`。
- ORM 表、列、索引与实际 SQLite schema 对比。
- `contents` 与 FTS 索引的一致性。
- 分发队列领取、重试和唯一性查询计划。
- Agent context summary 等外键列的索引检查。
- Alembic 当前 revision 与迁移目录 head 比较。

健康检查只读，使用 SQLAlchemy Inspector 检查实际表、列和索引，FTS 与 SQLite 完整性单独检查。`scripts/check_database_schema.py --db 路径` 对指定测试库执行升级和检查；默认复用 `backend/.test-runtime/regression.db`，不创建随机临时数据库。
