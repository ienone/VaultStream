# 数据库 schema gate 与数据库文档存在漂移

## 状态

archived（2026-09-06 已解决）

## 原问题

- `schema_metadata` 没有在数据库文档中作为运行期门禁结构说明。
- `ensure_schema_metadata()` 曾在每次调用时直接写入当前 `REQUIRED_SCHEMA_VERSION`；历史迁移也调用该函数，因此旧迁移在今天运行时可能越级声称已完成最新版本。
- 门禁只检查版本和部分表是否存在，缺少关键列、索引的结构证据。一个版本号为当前值但缺少结构的数据库仍可能被过度乐观地判定。

## 影响范围

- 后端模块：database、config-system、search-rag、contents。
- 数据：SQLite schema、FTS、`content_embeddings`、`schema_metadata` 及后续运行期表。
- 用户影响：历史数据库可能缺少关键列、索引或触发器，但健康检查仍报告通过。

## 根因

元数据表初始化、迁移版本记录和结构校验使用了同一个函数；版本号被当前代码常量覆盖，而不是由实际完成的迁移步骤推进。同时门禁缺少覆盖当前核心结构的 manifest。

## 解决记录（2026-09-06）

- `ensure_schema_metadata()` 只创建元数据表，不再写版本。
- 新增 `record_schema_version(conn, version)`；m29 至 m33 在自身结构变更后分别显式记录 29 至 33，且旧迁移不会降低较新数据库的版本。
- 启动初始化先补齐当前 ORM、兼容列、索引和 FTS，再检查完整性、外键、关键表/列/索引及领域门禁；只有结构完整时才推进当前版本。
- schema manifest 覆盖内容编辑与语义索引、任务账本、消息盒子、知识事件、播放书签和 Agent context summary 的关键列及索引。
- 数据库文档已明确 `schema_metadata` 的运行期职责，以及“版本号不能替代结构校验”的边界。

## 验证证据

- 缺少关键索引或关键列、但版本号仍为 33 的隔离 SQLite 库均返回 `degraded`。
- `ensure_schema_metadata()` 不会把已记录的 31 提升到当前版本。
- schema gate / FTS 聚焦测试 **7 passed**。
- 后端非 integration 套件在沙盒内为 **943 passed / 1 个仅因端口权限失败 / 4 skipped / 9 deselected**；包含该用例的 dev controller 文件在沙盒外 **10 passed**，合并口径为 **944 passed / 4 skipped / 9 deselected**。
- 只读检查仓库实验数据库 `backend/data/vaultstream.db`：schema 33、integrity `ok`、0 个外键问题，关键表/列/索引无缺失，FTS 8 条索引与 8 条内容一致。

## 关联代码与文档

- `backend/app/core/database.py`
- `backend/app/core/schema_gate.py`
- `backend/migrations/m29_create_schema_metadata.py` 至 `m33_create_media_bookmarks.py`
- `backend/tests/test_database_schema_gate.py`
- `backend/tests/test_database_fts.py`
- `../../backend/database.md`
