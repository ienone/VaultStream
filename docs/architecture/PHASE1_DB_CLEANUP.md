# Phase 1 DB Cleanup（DB/枚举去旧）

## 目标

收敛分发队列到 Phase 1 新语义，删除旧链路遗留字段与状态：

- `content_queue_items`：
  - 删除列：`needs_approval`、`approved_at`
  - 状态收敛：`pending` / `skipped` / `canceled` -> `failed`（终态，不再重试）
- `distribution_rules`：
  - 删除列：`auto_approve_conditions`
  - 删除前自动备份到 `system_settings`

## 迁移行为（幂等）

应用启动会执行 `init_db()`，其中包含本次迁移：

1. 归一化历史大写状态值（如 `SCHEDULED` -> `scheduled`）
2. 收敛旧队列状态到 `failed`
3. 删除 `content_queue_items` 旧审批列
4. 备份并删除 `distribution_rules.auto_approve_conditions`

备份 key：

- `system_settings.key = migration.phase1.auto_approve_conditions_backup`

备份值包含：

- `migrated_at`
- `row_count`
- `rows`（规则 ID、名称、`approval_required`、旧 `auto_approve_conditions`）

## 一键执行（云端）

在服务根目录执行：

```bash
cd backend
bash scripts/migrate_phase1_db_cleanup.sh
```

或：

```bash
cd backend
python scripts/migrate_phase1_db_cleanup.py
```

Windows：

```powershell
cd backend
.\scripts\migrate_phase1_db_cleanup.ps1
```

## 迁移后验证

1. 列检查：
   - `PRAGMA table_info(content_queue_items)` 不包含 `needs_approval` / `approved_at`
   - `PRAGMA table_info(distribution_rules)` 不包含 `auto_approve_conditions`
2. 状态检查：
   - `SELECT DISTINCT status FROM content_queue_items`
   - 仅应出现：`scheduled` / `processing` / `success` / `failed`
3. 备份检查（如历史存在旧规则列数据）：
   - `SELECT key, updated_at FROM system_settings WHERE key='migration.phase1.auto_approve_conditions_backup'`

## 回滚说明

- 本迁移为“收敛+删列”，不建议结构回滚。
- 若需恢复 `auto_approve_conditions` 历史数据，可从 `system_settings` 备份 key 读取并人工恢复到新规则设计。
