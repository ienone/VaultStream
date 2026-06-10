# 数据库 schema gate 与数据库文档存在漂移

## 状态

active

## 现象

- `docs/backend/database.md` 描述当前 ORM 表和运行期 FTS/兼容结构，但没有把 `schema_metadata` 表作为运行期 schema gate 的事实讲清楚。
- `backend/app/core/database.py` 启动时依次执行 `Base.metadata.create_all`、`ensure_content_embeddings_schema()`、`ensure_content_fts()`、`ensure_schema_metadata()`。
- `ensure_schema_metadata()` 会写入 `REQUIRED_SCHEMA_VERSION`，随后 `validate_database_schema()` 检查 `schema_version >= REQUIRED_SCHEMA_VERSION`。这使版本校验存在“启动时自我覆盖为通过”的风险，不能证明历史库真的完成了结构迁移。

## 影响范围

- 后端模块：database、config-system、search-rag、contents。
- 数据：SQLite schema、FTS 表、content_embeddings、schema_metadata。
- 用户影响：历史数据库可能缺少关键列/索引/触发器，但 schema version 已被启动流程提升，健康检查可能给出过度乐观结果。

## 复现方式

1. 打开 `backend/app/core/database.py`，查看应用初始化调用顺序。
2. 打开 `backend/app/core/schema_gate.py`，查看 `ensure_schema_metadata()` 和 `validate_database_schema()`。
3. 构造一个缺少某个关键结构但可启动的 SQLite 库，观察启动过程可能先写入 required schema version。

## 根因分析

- 初始化、兼容补齐、迁移基线和健康校验混在启动流程中。
- `schema_version` 被当前进程主动写入，而不是由已完成的结构迁移结果推进。
- 数据库文档强调 ORM 表，未充分记录非 ORM 运行期表和 schema gate 的语义限制。

## 关联代码

- `backend/app/core/database.py`
- `backend/app/core/schema_gate.py`
- `backend/tests/test_database_schema_gate.py`
- `backend/tests/test_database_fts.py`

## 关联文档

- `../backend/database.md`
- `../backend/modules/search-rag.md`
- `../backend/modules/config-system.md`

## 修复建议

- 最小修复：在数据库文档中补充 `schema_metadata` 是运行期表，并明确当前版本检查不能替代完整迁移校验。
- 中期修复：`ensure_schema_metadata()` 只在确认结构补齐成功后提升版本；或让 `validate_database_schema()` 校验关键列、索引、触发器和 FTS 表清单。
- 长期修复：引入明确迁移机制或 schema manifest，避免 `create_all`、手写补齐和 version gate 混用。

## 验证方式

- 自动测试：构造缺少关键列/索引但 `schema_metadata=REQUIRED_SCHEMA_VERSION` 的临时 SQLite 库，`validate_database_schema()` 必须返回 degraded。
- 回归测试：`.venv\Scripts\python.exe -m pytest backend/tests/test_database_schema_gate.py backend/tests/test_database_fts.py -q`。
- 文档校验：`docs/backend/database.md` 明确列出 ORM 表、运行期表和 schema gate 限制。
