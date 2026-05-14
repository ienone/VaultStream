# 数据库结构说明

## 1. `contents` 表 (核心内容存储)

采用“通用字段 + 平台特有字段 (JSON)”的混合存储模式，兼顾查询效率与扩展性。

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `id` | Integer | 自增主键 |
| `platform` | Enum | 平台标识 (`bilibili`, `twitter`, `xiaohongshu` 等) |
| `platform_id` | String | 平台原生 ID (如 B 站 BV 号、推文 ID) |
| `url` | Text | 原始提交链接 |
| `canonical_url` | Text | 规范化后的去重键（用于 `(platform, canonical_url)` 去重） |
| `clean_url` | Text | 净化后的标准链接 |
| `status` | Enum | 状态机: `unprocessed`, `processing`, `parse_success`, `parse_failed` |
| `tags` | JSON | 用户自定义标签列表 `["Tech", "Meme"]` |
| `is_nsfw` | Boolean | 是否为敏感内容 |
| `source` | String | 来源标识 (如 `web_test`, `ios_shortcut`) |
| 通用元数据 | | |
| `title` | Text | 标题 |
| `body` | Text | 正文/描述 |
| `summary` | Text | AI 摘要，用于详情展示、RAG chunk 与全文检索 |
| `author_name` | String | 作者昵称 |
| `author_id` | String | 作者平台唯一 ID |
| `cover_url` | Text | 封面图链接 |
| `media_urls` | JSON | 媒体资源列表 (图片、视频流地址) |
| 通用互动数据 | | |
| `view_count` | Integer | 播放/阅读数 |
| `like_count` | Integer | 点赞数 |视频解析
| `collect_count` | Integer | 收藏数 |
| `share_count` | Integer | 分享数 |
| `comment_count` | Integer | 评论数 |
| 扩展数据 | | |
| `extra_stats` | JSON | 平台特有数据 (如 B 站投币 `coin`、弹幕 `danmaku`) |
| `archive_metadata` | JSON | [Archive Blob] 归档存档信息，包含 `processed_archive` (归档) 与 `raw_api_response` (原始响应) |
| `context_data` | JSON | [Context Slot] 结构化关联上下文 (如知乎关联问题、微博引用内容) |
| `rich_payload` | JSON | [Rich Payload] 富媒体/交互组件载荷 (用于前端动态组件渲染) |
| 时间戳 | | |
| `published_at` | DateTime | 内容在原平台的发布时间 |视频解析
| `created_at` | DateTime | 记录创建时间 |

## 3. 解析失败与回滚字段（最小实现）

为了支持最小化的回滚和人工修复流程，`contents` 表新增以下字段用于记录解析失败信息：

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `failure_count` | Integer | 累计解析失败次数（默认 0） |
| `last_error` | Text | 最近一次失败的简要错误信息 |
| `last_error_type` | String | 最近一次失败的异常类型名称 |
| `last_error_detail` | JSON | 可选的失败详情（如简要堆栈/上下文），仅供内部排查使用 |
| `last_error_at` | DateTime | 最近一次失败发生的 UTC 时间 |

注意：这些字段由 worker 在解析异常时写入；成功解析后会清理 `last_error*` 字段但保留 `failure_count` 作为历史统计。

架构初始化：应用启动时会通过 `Base.metadata.create_all` 创建 ORM 表，并在 `init_db()` 中补齐运行期必需的兼容结构，例如 `contents_fts`。历史库升级仍需要按版本执行 `backend/migrations/` 与 `scripts/` 中的一次性迁移脚本。

## 4. 索引 (M3)

### 复合索引
针对管理端的常用查询路径，建立了以下索引：
- `(platform, created_at)`: 按平台和时间排序。
- `(status, created_at)`: 按状态（如“待处理”）和时间排序。
- `(is_nsfw, created_at)`: 按敏感分级和时间排序。

### 全文搜索 (FTS5)
针对 SQLite 平台，利用 `FTS5` 扩展创建了虚拟表 `contents_fts`，并配置了自动化触发器。
- **搜索范围**: 标题 (`title`)、正文 (`body`)、摘要 (`summary`)。
- **同步机制**: `app.core.database.ensure_content_fts()` 创建 `contents_fts` 及 `AFTER INSERT/UPDATE/DELETE` 触发器，并在启动时 backfill 缺失行。
- **健康检查**: `/api/v1/health` 会返回 `checks.database.fts`，包含 `available`、`indexed_rows`、`content_rows`、`triggers`。

## 4.1 语义检索索引 (`content_embeddings`)

语义检索使用普通 SQLite 表保存向量 JSON，当前尚未依赖 sqlite-vec/sqlite-vss 扩展；方案评估见 `docs/architecture/VECTOR_SEARCH_EVALUATION.md`。

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `content_id` | Integer | 外键，关联 `contents.id`，删除内容时级联清理 |
| `chunk_index` | Integer | `-1` 表示全文/摘要，`0+` 表示 RAG chunk |
| `chunk_title` | Text | chunk 标题 |
| `embedding_model` | String | 模型签名，包含模型名与维度 |
| `embedding` | JSON | 向量数组 |
| `text_hash` | String | 文本 hash，用于避免重复索引 |
| `source_text` | Text | 用于检索解释的原始文本片段 |

`EmbeddingService.search_similar()` 会限制候选范围后在应用层计算相似度，并记录候选数与耗时。后续如引入 sqlite-vec，需要同步迁移本表或新增虚拟表。

## 5. 任务队列表 (`tasks`)

后端采用数据库任务表执行解析任务分发，不依赖 Redis。

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `id` | Integer | 自增主键 |
| `task_type` | String | 任务类型 (如 `parse_content`) |
| `payload` | JSON | 任务负载 (如 `{"content_id": 123}`) |
| `status` | Enum | `pending`, `running`, `completed`, `failed` |
| `priority` | Integer | 优先级 (越大越靠前) |
| `retry_count`| Integer | 已重试次数 |

## 5.1 分发队列表 (`content_queue_items`)

分发队列按 `(content_id, rule_id, bot_chat_id)` 建模，避免同一内容在同一规则/目标下重复入队。

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `content_id` | Integer | 外键，关联 `contents.id` |
| `rule_id` | Integer | 外键，关联 `distribution_rules.id` |
| `bot_chat_id` | Integer | 外键，关联 `bot_chats.id` |
| `status` | Enum | `scheduled`, `processing`, `success`, `failed` |
| `attempt_count` | Integer | 已尝试次数 |
| `max_attempts` | Integer | 最大尝试次数 |
| `next_attempt_at` | DateTime | 下次可重试时间 |
| `last_error` / `last_error_type` / `last_error_at` | 多类型 | 最近一次推送失败诊断 |

`/api/v1/health` 的 `checks.background_tasks.distribution_queue` 会暴露 scheduled/processing/failed/success 与 retryable_failed 统计。


## 2. `pushed_records` 表 (分发追踪)

用于实现分发去重逻辑。

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `id` | Integer | 主键 |
| `content_id` | Integer | 外键，关联 `contents.id` |
| `target_platform` | String | 目标平台标识（统一为 `telegram` / `qq`） |
| `message_id` | String | 推送成功后的消息 ID (用于后续更新或撤回) |
| `pushed_at` | DateTime | 推送时间 |

## 6. `content_sources` 表（来源流水）

用于记录每次分享请求的来源快照，便于审计与回放。

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `id` | Integer | 自增主键 |
| `content_id` | Integer | 外键，关联 `contents.id` |
| `source` | String | 来源标识（如 `android_share`） |
| `tags_snapshot` | JSON | 后端标准化后的标签快照 |
| `note` | Text | 用户备注 |
| `client_context` | JSON | 客户端上下文 |
| `created_at` | DateTime | 记录创建时间 |

## 7. 架构初始化基线（当前实现）

全新或回放环境请确保以下架构脚本已经执行到位：

- 分发目标重构：`m8_distribution_target_refactor.py`、`m9_finalize_targets_migration.py`
- 旧排期字段收口：`m11_drop_legacy_content_schedule_columns.sql`
- Bot 配置链路：`m12_add_bot_config_table.sql`、`m14_bind_bot_chats_to_config.py`、`m15_add_napcat_access_token.py`
- 状态机统一：`m17_replace_legacy_content_status.sql`
- Phase 1 队列去旧：`scripts/migrate_phase1_db_cleanup.py`（删除 `needs_approval` / `approved_at` / `auto_approve_conditions`）

治理约束：

- 运行时只依赖当前结构，不保留旧字段兼容分支。
- 中间态/一次性变更脚本仅用于升级，不应作为运行时逻辑输入。
- 已归档的一次性数据处理脚本统一放置在 `scripts/archive/`。
