# DB_CLEANUP（数据库迁移与清理基线）

> 本文档作为后续发版迁移脚本（release migration script）的执行基线。

## 1. 目的与范围

当前仓库的数据库迁移以“应用启动幂等迁移”为主（`backend/app/core/database.py`）。

本文件记录：

- 已落地的迁移函数与变更内容（用于脚本化对齐）
- 需要在下一版发布脚本中显式覆盖的 SQL 事项
- 上线前后的核对清单

## 2. 当前已落地迁移（代码现状）

入口：`init_db()`

执行顺序：

1. `Base.metadata.create_all`
2. `_migrate_content_embeddings_table`
3. `_migrate_review_status_lowercase`
4. `_migrate_distribution_target_backfill_watermark`
5. `_migrate_phase1_distribution_cleanup`

### 2.1 Phase 1 清理（分发链路）

#### A. `contents.review_status` 大写值归一化

函数：`_migrate_review_status_lowercase()`

映射：

- `PENDING -> pending`
- `APPROVED -> approved`
- `REJECTED -> rejected`
- `AUTO_APPROVED -> auto_approved`

#### B. `distribution_targets.backfill_watermark` 补列与回填

函数：`_migrate_distribution_target_backfill_watermark()`

行为：

- 若列不存在：`ALTER TABLE distribution_targets ADD COLUMN backfill_watermark DATETIME`
- 回填：`backfill_watermark = COALESCE(backfill_watermark, created_at, CURRENT_TIMESTAMP)`

#### C. `content_queue_items` 状态收敛 + 旧列删除

函数：`_migrate_phase1_distribution_cleanup()`

内部动作：

- `_migrate_queue_status_cleanup()`
  - 历史大写状态归一化（`SCHEDULED` 等）
  - `pending/skipped/canceled` 统一迁移为 `failed`
  - 迁移时补 `last_error_type/last_error/last_error_at`
- `_drop_queue_legacy_approval_columns()`
  - 删除：`needs_approval`、`approved_at`
  - 若 SQLite 不支持 `DROP COLUMN`，走重建表回填 `_rebuild_content_queue_items_without_legacy_columns()`

#### D. `distribution_rules.auto_approve_conditions` 备份后清理

函数：`_migrate_phase1_distribution_cleanup()`

内部动作：

- `_backup_auto_approve_conditions()`
  - 备份到 `system_settings`：
    - `key = migration.phase1.auto_approve_conditions_backup`
- `_drop_rule_auto_approve_column()`
  - 尝试删除 `auto_approve_conditions`
  - 低版本 SQLite 不支持时记录 warning（不阻断启动）

### 2.2 Phase 2 语义检索基础设施迁移

#### E. `content_embeddings` 表补齐

函数：`_migrate_content_embeddings_table()`

行为：

- `CREATE TABLE IF NOT EXISTS content_embeddings (...)`
- 缺列补齐：
  - `source_text`
  - `text_hash`
  - `embedding_model`
- 索引补齐：
  - `uq_content_embeddings_content_id`
  - `ix_content_embeddings_indexed_at`
  - `ix_content_embeddings_model`
  - `ix_content_embeddings_text_hash`

## 3. 下一版发布脚本应覆盖项（建议）

> 建议把当前“启动时迁移”脚本化为可审计的 release SQL/脚本，避免线上隐式变更。

### 3.1 前置保护

1. 数据库全量备份（必做）
2. 记录迁移前版本号与时间戳
3. 若存在 `distribution_rules.auto_approve_conditions`，先导出备份 JSON

### 3.2 脚本最小变更集

1. 归一化 `contents.review_status`
2. 补 `distribution_targets.backfill_watermark` 并回填
3. 清理 `content_queue_items` 的历史状态值
4. 删除 `content_queue_items.needs_approval/approved_at`
5. 备份并删除 `distribution_rules.auto_approve_conditions`
6. 创建/补齐 `content_embeddings` 与索引

### 3.3 迁移后校验 SQL（建议纳入脚本）

```sql
-- 1) review_status 校验
SELECT review_status, COUNT(*) FROM contents GROUP BY review_status;

-- 2) 队列状态仅保留新语义
SELECT status, COUNT(*) FROM content_queue_items GROUP BY status;

-- 3) 旧列校验（应不存在）
PRAGMA table_info(content_queue_items);
PRAGMA table_info(distribution_rules);

-- 4) backfill_watermark 覆盖率
SELECT COUNT(*) AS null_count
FROM distribution_targets
WHERE backfill_watermark IS NULL;

-- 5) content_embeddings 结构与索引
PRAGMA table_info(content_embeddings);
PRAGMA index_list(content_embeddings);

-- 6) 备份键存在性
SELECT key, updated_at
FROM system_settings
WHERE key = 'migration.phase1.auto_approve_conditions_backup';
```

## 4. 风险与回滚策略

- 本清理包含删列与状态收敛，不建议结构级回滚。
- 回滚策略应以“备份库恢复”为主。
- `auto_approve_conditions` 恢复可基于 `system_settings` 备份键人工回放。

## 5. 文件命名说明

原 `PHASE1_DB_CLEANUP.md` 已更名为 `DB_CLEANUP.md`，后续统一在本文件持续追加各 Phase 的 DB 迁移变更记录。
