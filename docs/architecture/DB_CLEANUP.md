# DB_CLEANUP（数据库迁移与清理基线）

> 本文档用于把“启动时幂等迁移”（`backend/app/core/database.py`）与历史一次性迁移脚本（`backend/migrations`）对齐，形成后续“统一迁移”的可执行清单与核对项。

## 1. 目的与范围

当前仓库存在两套并行的迁移形态：

- **启动时幂等迁移**：随应用启动执行（`backend/app/core/database.py:init_db()`），目标是“旧库兼容 + 新库自举”。
- **一次性迁移脚本（release scripts）**：存放在 `backend/migrations/`，按 `m{N}_*.sql/.py` 命名，目标是“发版时显式执行、可审计”。

本文档记录：

- 代码已经落地的迁移函数/脚本与行为（以代码为准）
- 为“统一迁移”仍需补齐的缺口与不一致项
- 上线前后的核对清单

## 2. 当前迁移现状（以代码为准）

### 2.1 启动时幂等迁移（`init_db()`）

入口：`backend/app/core/database.py:init_db()`

执行顺序（当前代码）：

1. `Base.metadata.create_all`
2. `_migrate_content_embeddings_table(conn)`（同一连接/事务内执行）
3. `_ensure_content_queue_claim_indexes(conn)`（同一连接/事务内执行）
4. `_migrate_review_status_lowercase()`（新连接）
5. `_migrate_distribution_target_backfill_watermark()`（新连接）
6. `_migrate_phase1_distribution_cleanup()`（新连接）
7. `_migrate_single_bot_per_platform()`（新连接）
8. `_migrate_bot_runtime_per_platform()`（新连接）

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

- 若表不存在则跳过（防御性：旧库可能尚未引入分发目标表）
- 若列不存在：`ALTER TABLE distribution_targets ADD COLUMN backfill_watermark DATETIME`
- 回填：`backfill_watermark = COALESCE(backfill_watermark, created_at, CURRENT_TIMESTAMP)`

#### C. `content_queue_items` 队列领取热点索引补齐

函数：`_ensure_content_queue_claim_indexes(conn)`

行为：为领取/重试等高频查询补齐索引（幂等）：

- `ix_queue_claim_scheduled_priority (status, priority DESC, scheduled_at, id)`
- `ix_queue_claim_failed_retry (status, next_attempt_at, priority DESC, scheduled_at, id)`
- `ix_queue_claim_status_lock (status, locked_at)`

#### D. Phase 1 清理（分发链路：队列状态/旧列/旧规则字段）

函数：`_migrate_phase1_distribution_cleanup()`

内部动作：

- `_migrate_queue_status_cleanup()`
  - 历史大写状态归一化（`SCHEDULED/PROCESSING/SUCCESS/FAILED/PENDING/SKIPPED/CANCELED` 等）
  - `pending/skipped/canceled` 统一收敛到 `failed`
  - 迁移时补 `last_error_type/last_error/last_error_at`（幂等补齐）
- `_drop_queue_legacy_approval_columns()`
  - 删除：`content_queue_items.needs_approval`、`content_queue_items.approved_at`
  - 先尝试 `ALTER TABLE ... DROP COLUMN`；不支持时走“重建表回填”兼容逻辑
- `_backup_auto_approve_conditions()`
  - 备份 `distribution_rules.auto_approve_conditions` 到 `system_settings`
  - `key = migration.phase1.auto_approve_conditions_backup`（写入 JSON 结构含 row_count/rows/migrated_at）
- `_drop_rule_auto_approve_column()`
  - 尝试删除 `distribution_rules.auto_approve_conditions`
  - SQLite 不支持时记录 warning（不阻断启动）

#### E. Phase 2：语义检索基础设施（`content_embeddings`）

函数：`_migrate_content_embeddings_table(conn)`

行为：

- `CREATE TABLE IF NOT EXISTS content_embeddings (...)`
- 对旧库进行“缺列补齐”（幂等）：`source_text` / `text_hash` / `embedding_model`
- 索引补齐（幂等）：
  - `uq_content_embeddings_content_id`
  - `ix_content_embeddings_indexed_at`
- `ix_content_embeddings_model`
- `ix_content_embeddings_text_hash`

#### F. Bot 配置收敛：每个平台仅保留一条 BotConfig

函数：`_migrate_single_bot_per_platform()`

行为：

- 以 `platform` 为分组维度收敛 `bot_configs`，选择规则：
  - `enabled DESC`
  - `is_primary DESC`
  - `id ASC`
- 将同平台重复配置下的 `bot_chats` 先做按 `chat_id` 去重，再迁移到保留记录
  - 同时清理 `distribution_targets(rule_id, bot_chat_id)` 唯一冲突
  - 同时清理 `content_queue_items(content_id, rule_id, bot_chat_id)` 唯一冲突
- 合并保留记录缺失字段（`name`、凭证、`bot_id`、`bot_username`）
- `enabled` 取同平台记录的“逻辑或”，避免升级后把原本仍在使用的平台误关停
- Telegram 平台优先用 `bot_runtime` 回填 `bot_id/bot_username`
- 删除重复记录
- 建立唯一索引：
  - `uq_bot_configs_platform (platform)`

目的：

- 停止“同平台多 Bot + 主配置切换”的历史模型继续扩散
- 为前后端收敛到“Telegram 1 个 / QQ 1 个配置面板”打基础
- 避免 `bot_configs`、`bot_runtime`、`bot_chats` 之间出现重复身份来源

#### G. Bot 运行态收敛：`bot_runtime` 按平台唯一

函数：`_migrate_bot_runtime_per_platform()`

行为：

- 为 `bot_runtime` 补齐 `platform` 列，默认值为 `telegram`
- 回填空值为 `telegram`
- 若同一平台存在多条运行态记录：
  - 保留最早一条
  - 合并缺失字段
  - 删除重复记录
- 建立唯一索引：
  - `uq_bot_runtime_platform (platform)`

目的：

- 把运行态从“全局单例”收敛成“按平台唯一”
- 为 Telegram / QQ 独立状态展示与后续扩展保留正确语义

### 2.2 一次性迁移脚本（`backend/migrations/`）

注意：这些脚本目前**不被应用自动调用**（代码内未发现统一 runner/应用记录表），通常按发版需要手工执行。

已存在脚本概览（按文件名）：

- `m6_add_scheduled_at.sql`：为 `contents` 增加 `scheduled_at` 与索引（后续被 m11 清理）。
- `m7_add_is_manual_schedule.sql`：为 `contents` 增加 `is_manual_schedule`（后续被 m11 清理）。
- `m8_add_render_config.sql`：为 `distribution_rules` 增加 `render_config`。
- `m8_distribution_target_refactor.py`：将 `DistributionRule.targets(JSON)` 迁移到 `distribution_targets` 表（含自动创建 BotChat）。
- `m9_finalize_targets_migration.py`：最终清理 `rule.targets` 遗留数据并置空。
- `m10_cleanup_legacy_distribution.sql`：将 `contents.status='distributed'` 归一化回 `pulled`。
- `m11_drop_legacy_content_schedule_columns.sql`：删除 `contents.scheduled_at / contents.is_manual_schedule`。
- `m12_add_bot_config_table.sql`：新增 `bot_configs` 并为 `bot_chats` 增加 `bot_config_id` 与相关索引。
- `m13_add_realtime_events.sql`：新增 `realtime_events` outbox 表与索引。
- `m14_bind_bot_chats_to_config.py`：历史 `bot_chats` 绑定到主 `bot_configs`，并用 trigger 强制非空。
- `m15_add_napcat_access_token.py`：为 `bot_configs` 增加并回填 `napcat_access_token`。
- `m16_status_pipeline_indexes.sql`：状态看板索引优化（⚠ 见 3.3：当前与现有 schema 存在冲突）。
- `m17_replace_legacy_content_status.sql`：将旧 `contents.status` 物理迁移到新四态（`parse_success/parse_failed` 等）。
- `m18_backfill_parse_success_for_parsed_contents.sql`：回填历史“已具备解析特征但仍 unprocessed”的记录为 `parse_success`。
- `m19_backfill_queue_success_for_existing_rules.py`：为历史 `parse_success` 内容补齐 “success 队列项”。
- `m20_add_api_keys_table.sql`：新增 `api_keys` 表与索引。
- `m21_v2_structure_field_replacement.sql`：为 `contents` 增加 v2 结构字段（`context_data/rich_payload/archive_metadata/deleted_at`）。
- `m22_rename_description_to_body_add_summary.py`：`contents.description -> body`，并新增 `summary`。
- `m23_add_discovery_system.py`：增加发现系统字段/表（`contents` 新字段、`discovery_sources`、`bot_chats` 新字段）。
- `m24_add_discovery_aggregation.py`：`contents` 增加 `parent_id/is_synthesis` 与索引。
- `m25_normalize_layout_type.py`：归一化枚举残留（`layout_type*`、`content_queue_items.status` 大写残留）并回填 NULL。
- `m26_add_content_discovery_links.py`：创建 `content_discovery_links` 并迁移 `context_data.source_links`。
- `m27_add_content_discovery_source_id.py`：为 `contents` 增加 `discovery_source_id` 并回填。
- `m28_drop_redundant_system_settings_key_index.sql`：删除冗余索引 `ix_system_settings_key`。
- `add_layout_type.py` / `repair_layout_type.py` / `phase7_structured_fields.py`：历史补丁脚本（非 m{N} 命名，但同属一次性迁移性质）。

## 3. 面向“统一迁移”的缺口与不一致（对照 `backend/migrations`）

### 3.1 需要补齐为 release migrations 的“隐式迁移”（目前仅存在于 `init_db()`）

对后续统一迁移而言，以下变更目前仍是“应用启动隐式执行”，在 `backend/migrations/` 中**没有**对应脚本记录：

1. `contents.review_status` 大写→小写归一化（`_migrate_review_status_lowercase`）
2. `distribution_targets.backfill_watermark` 补列与回填（`_migrate_distribution_target_backfill_watermark`）
3. Phase 1 清理（`_migrate_phase1_distribution_cleanup`：队列状态收敛、删列、备份并删字段）
4. `content_embeddings` 的“旧库补齐列/索引”逻辑（`_migrate_content_embeddings_table`）
5. 队列领取热点索引补齐（`_ensure_content_queue_claim_indexes`）
6. Bot 单平台单配置收敛（`_migrate_single_bot_per_platform`）
7. Bot 运行态按平台唯一收敛（`_migrate_bot_runtime_per_platform`）

如果目标是“把所有迁移都统一到 `backend/migrations` 并可追踪/可回放”，这些应被补齐为显式脚本（建议使用新的 `m{N}` 编号或引入统一 runner 后自动追踪），同时避免与 `init_db()` 双跑造成重复/冲突。

### 3.2 `backend/migrations` 脚本的执行边界需要在文档中明确

当前仓库缺少“已应用迁移记录表/runner”的事实意味着：

- `backend/migrations` 里的脚本**默认不会自动生效**；
- DB 结构最终形态更依赖 `Base.metadata.create_all` 与 `init_db()`；
- 统一迁移之前，需要明确“哪些脚本必须执行、执行顺序、幂等保障、与启动幂等迁移的关系（替代/叠加/废弃）”。

### 3.3 已发现的不一致/潜在冲突（需要修正记录）

1. `backend/migrations/m16_status_pipeline_indexes.sql` 当前对 `content_queue_items(needs_approval, approved_at)` 建索引，
   但：
   - 现有 ORM 模型已移除这两列；
   - `init_db()` 的 Phase 1 清理会主动删除这两列；
   因此该脚本在“新 schema/已清理”库上将无法执行。
   统一迁移时应当：
   - 要么废弃/替换 m16（例如只保留对 `contents(status, id)` 的索引优化）；
   - 要么将其改为具备列存在性判断的脚本（SQL 很难跨 SQLite 版本做条件判断，通常用 Python 更稳妥）。

2. `m11_drop_legacy_content_schedule_columns.sql` / `m21_v2_structure_field_replacement.sql` 使用的 SQLite 方言特性（`DROP COLUMN`、`ADD COLUMN IF NOT EXISTS`）
   依赖 SQLite 版本；而 `init_db()` 里同类操作采取了“先探测再执行/失败重建”的兼容策略。
   统一迁移时需要在文档里明确目标 SQLite 最低版本，或为这些 release scripts 增加兼容实现。

## 4. Release 脚本最小集（仅用于“把 init_db 隐式迁移脚本化”的场景）

> 若目标是把当前 `init_db()` 的隐式迁移迁出为“发版脚本”，最小可覆盖项如下（不含 `backend/migrations` 里已有的历史脚本）。

### 4.1 前置保护

1. 数据库全量备份（必做）
2. 记录迁移前版本号与时间戳
3. 若存在 `distribution_rules.auto_approve_conditions`，先导出备份 JSON（或依赖 Phase 1 自动备份键）

### 4.2 脚本最小变更集

1. 归一化 `contents.review_status`
2. 补 `distribution_targets.backfill_watermark` 并回填
3. 清理 `content_queue_items` 的历史状态值（含 `pending/skipped/canceled -> failed`）
4. 删除 `content_queue_items.needs_approval/approved_at`
5. 备份并删除 `distribution_rules.auto_approve_conditions`
6. 创建/补齐 `content_embeddings` 与索引
7. 补齐队列领取热点索引（`ix_queue_claim_*`）
8. 收敛 `bot_configs` 为每个平台唯一一条，并建立 `uq_bot_configs_platform`
9. 收敛 `bot_runtime` 为每个平台唯一一条，并建立 `uq_bot_runtime_platform`

## 5. 迁移后核对清单（建议纳入脚本）

```sql
-- 1) review_status 校验
SELECT review_status, COUNT(*) FROM contents GROUP BY review_status;

-- 2) contents.status 旧值清理 / 新四态分布（如有执行 m10/m17）
SELECT status, COUNT(*) FROM contents GROUP BY status;
SELECT COUNT(*) AS distributed_count FROM contents WHERE status = 'distributed';

-- 3) 队列状态分布
SELECT status, COUNT(*) FROM content_queue_items GROUP BY status;

-- 4) 旧列校验（应不存在）
PRAGMA table_info(content_queue_items);
PRAGMA table_info(distribution_rules);
PRAGMA table_info(contents);

-- 5) backfill_watermark 覆盖率
SELECT COUNT(*) AS null_count
FROM distribution_targets
WHERE backfill_watermark IS NULL;

-- 6) content_embeddings 结构与索引
PRAGMA table_info(content_embeddings);
PRAGMA index_list(content_embeddings);

-- 7) Phase1 备份键存在性
SELECT key, updated_at
FROM system_settings
WHERE key = 'migration.phase1.auto_approve_conditions_backup';

-- 8) bot_configs 平台唯一性校验
SELECT platform, COUNT(*) AS cnt
FROM bot_configs
GROUP BY platform
HAVING COUNT(*) > 1;

PRAGMA index_list(bot_configs);

-- 9) bot_runtime 平台唯一性校验
SELECT platform, COUNT(*) AS cnt
FROM bot_runtime
GROUP BY platform
HAVING COUNT(*) > 1;

PRAGMA table_info(bot_runtime);
PRAGMA index_list(bot_runtime);
```

## 6. 风险与回滚策略

- 本清理包含删列与状态收敛，不建议结构级回滚。
- 回滚策略应以“备份库恢复”为主。
- `auto_approve_conditions` 恢复可基于 `system_settings` 备份键人工回放。

## 7. 文件命名说明

原 `PHASE1_DB_CLEANUP.md` 已更名为 `DB_CLEANUP.md`，后续统一在本文件持续追加各 Phase 的 DB 迁移与清理变更记录（以代码与脚本为准）。

## 8. 2026-03 单 Bot 收敛补充记录

### 8.1 背景

历史设计允许同平台维护多个 BotConfig 并通过 `is_primary` 切换主配置，但实际运行中引入了：

- 后端运行态与配置态的身份来源重复；
- 前端“添加 Bot / 设为主 Bot / 删除 Bot”交互复杂化；
- BotChat 与分发目标配置在语义上更难保持一致。

### 8.2 已落地变更

- 启动时新增 `_migrate_single_bot_per_platform()`：
  - 自动清理同平台重复 `bot_configs`
  - 迁移关联 `bot_chats`
  - 建立 `uq_bot_configs_platform`
- `POST /bot-config` 语义已收敛为“按平台 upsert”
  - 同平台已存在时不再创建第二条，而是更新原记录
- 首次创建时仍临时写入 `is_primary=True` 作为历史兼容，避免旧启动脚本/旧库判断失效
- `BotRepository.get_primary_config()` 逻辑已调整为“取平台唯一配置”

### 8.3 后续待继续推进

- 前端继续把运行态展示拆成更明确的 Telegram / QQ 分区
- 视需要再决定是否对 `bot_configs.is_primary` 做物理删列迁移

## 9. 2026-03 BotRuntime 平台化补充记录

### 9.1 已落地变更

- 启动时新增 `_migrate_bot_runtime_per_platform()`
  - 为 `bot_runtime` 增加 `platform`
  - 清理同平台重复运行态
  - 建立 `uq_bot_runtime_platform`
- `POST /bot/heartbeat` 已支持按 `platform` 写入运行态
- `GET /bot/runtime` 已支持 `?platform=telegram|qq`
- `GET /bot/status` 当前明确读取 Telegram 运行态，不再依赖全局单例

### 9.2 仍待推进

- QQ / Napcat 若后续需要主动心跳，可沿用同一 `platform` 运行态模型
- 前端可在后续版本把 Telegram / QQ 的运行态分开展示，而不是混在一张总卡里

## 10. 2026-03 Bot 管理链路进一步收口

### 10.1 已落地变更

- `BotChat` 明细/更新/删除/切换启用等路由已统一改为使用内部主键：
  - `GET /bot/chats/{bot_chat_id}`
  - `PATCH /bot/chats/{bot_chat_id}`
  - `DELETE /bot/chats/{bot_chat_id}`
  - `POST /bot/chats/{bot_chat_id}/toggle`
  - `GET|PUT /bot/chats/{bot_chat_id}/rules`
- `GET /bot/chats` 新增 `chat_id` 查询参数，用于“按真实目标 ID 精确过滤”而不是继续把 `chat_id` 当路径主键使用
- `BotChatRulesResponse` 现同时返回：
  - `bot_chat_id`
  - `chat_id`
- Bot 命令链路已切换为先调用 `GET /bot/chats?chat_id=...` 再解析内部 `id`，不再依赖旧的 `chat_id` 路由
- 前端 `bot_chats_provider`、群组管理页、编辑弹窗已全部切到内部 `id`
- `BotManagementPage` 中旧的“添加多个 Bot 向导”已删除，避免继续保留多 Bot UI 入口
- `POST /bot-config/{id}/activate` 已删除；`BotConfig` 接口不再暴露 `is_primary` 输入/输出字段

### 10.2 当前保留的历史兼容点

- 数据库表 `bot_configs` 仍保留 `is_primary` 列，仅用于历史数据排序与迁移收敛
- 启动迁移 `_migrate_single_bot_per_platform()` 仍会读取该列，以便旧库首次升级时稳定选出保留记录
- 新建平台配置时仍会临时写入 `is_primary=True`，作为未彻底删列前的兼容兜底

### 10.3 后续可选清理

- 若确认所有线上库都已完成单 Bot 收敛，可考虑新增一次性迁移，物理删除 `bot_configs.is_primary`
- 若后续 Telegram / QQ 的默认目标选择策略需要进一步显式化，可在 `BotChat` 上增加“默认命令目标”之类单独字段，避免复用排序语义
