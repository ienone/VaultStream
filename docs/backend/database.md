# 数据库结构说明

## 文档状态

active

## 当前实现来源

本文档描述当前 ORM 模型中的真实表结构，代码来源为 `backend/app/models/`。应用启动时通过 `Base.metadata.create_all` 创建 ORM 表，并在 `backend/app/core/database.py` 中补齐运行期需要的兼容结构，例如 SQLite FTS5。

当前 ORM 表共 20 张：

- 内容域：`contents`、`content_sources`、`discovery_sources`、`content_discovery_links`
- 搜索域：`content_embeddings`
- 系统/任务域：`tasks`、`system_settings`
- 分发域：`distribution_rules`、`distribution_targets`、`content_queue_items`、`pushed_records`
- Bot 域：`bot_configs`、`bot_chats`、`bot_runtime`
- Agent 域：`agent_sessions`、`agent_messages`、`agent_runs`、`agent_tool_calls`、`agent_confirmations`、`agent_context_summaries`

## `contents`

核心内容表，模型位于 `backend/app/models/content.py`。

| 字段 | 说明 |
| :--- | :--- |
| `id` | 主键 |
| `platform` | 平台枚举 |
| `url` / `canonical_url` / `clean_url` | 原始 URL、规范化去重 URL、清洗 URL |
| `status` | 解析状态 |
| `layout_type` / `layout_type_override` | 自动布局类型和用户覆盖布局 |
| `content_type` | 平台内容类型 |
| `failure_count` / `last_error*` | 解析失败统计和最近失败详情 |
| `review_status` / `reviewed_at` / `reviewed_by` / `review_note` | 审核状态和人工审核信息 |
| `queue_priority` | 分发队列优先级 |
| `tags` / `source_tags` | 用户标签和来源标签 |
| `is_nsfw` | NSFW 标记 |
| `source` / `source_type` | 来源标识和来源类型 |
| `ai_score` / `ai_reason` / `ai_tags` | AI 巡逻评分、原因和标签 |
| `discovered_at` / `discovery_state` / `expire_at` / `promoted_at` / `discovery_source_id` | 发现流状态 |
| `platform_id` | 平台原生 ID |
| `view_count` / `like_count` / `collect_count` / `share_count` / `comment_count` | 通用互动统计 |
| `extra_stats` | 平台特有统计 |
| `parent_id` / `is_synthesis` | 关联内容和合成内容标记 |
| `title` / `body` / `summary` | 标题、正文、摘要 |
| `author_name` / `author_id` / `author_avatar_url` / `author_url` | 作者信息 |
| `cover_url` / `cover_color` / `media_urls` | 封面、封面主色、媒体 URL |
| `context_data` / `rich_payload` / `archive_metadata` | 结构化上下文、富内容载荷、归档元数据 |
| `deleted_at` | 软删除时间 |
| `created_at` / `updated_at` / `published_at` | 创建、更新、平台发布时间 |

## 内容来源和发现表

### `content_sources`

记录每次分享/导入的来源快照。

| 字段 | 说明 |
| :--- | :--- |
| `id` | 主键 |
| `content_id` | 关联 `contents.id` |
| `source` | 客户端或导入来源 |
| `tags_snapshot` | 当次标签快照 |
| `note` | 用户备注 |
| `client_context` | 客户端上下文 |
| `created_at` | 创建时间 |

### `discovery_sources`

发现源配置表。

| 字段 | 说明 |
| :--- | :--- |
| `id` | 主键 |
| `kind` | 发现源类型 |
| `name` | 名称 |
| `enabled` | 是否启用 |
| `config` | 源配置 JSON |
| `last_sync_at` / `last_cursor` / `last_error` | 同步状态 |
| `sync_interval_minutes` | 同步间隔 |
| `created_at` / `updated_at` | 创建和更新时间 |

### `content_discovery_links`

内容和发现源的关联流水。

| 字段 | 说明 |
| :--- | :--- |
| `id` | 主键 |
| `content_id` | 关联 `contents.id` |
| `discovery_source_id` | 关联 `discovery_sources.id` |
| `url` | 来源 URL |
| `created_at` | 创建时间 |

## 搜索与语义索引

### `content_embeddings`

语义检索使用普通 SQLite 表保存向量 JSON，当前尚未依赖 sqlite-vec/sqlite-vss 扩展。模块说明见 `modules/search-rag.md`。

| 字段 | 说明 |
| :--- | :--- |
| `id` | 主键 |
| `content_id` | 关联 `contents.id`，内容删除时级联删除 |
| `chunk_index` | `-1` 表示全文/摘要，`0+` 表示语义分块 |
| `chunk_title` | 分块标题 |
| `embedding_model` / `embedding_model_signature` | 模型和模型签名 |
| `embedding` | 向量 JSON |
| `text_hash` | 文本 hash |
| `source_text` | 参与检索解释的原始文本 |
| `index_status` | pending/success/error 等索引状态 |
| `failure_reason` / `retry_count` / `last_attempted_at` / `last_indexed_at` | 索引失败和重试状态 |
| `indexed_at` / `created_at` / `updated_at` | 时间戳 |

## 系统与任务表

### `tasks`

数据库任务表，用于解析等后台任务。

| 字段 | 说明 |
| :--- | :--- |
| `id` | 主键 |
| `task_type` | 任务类型 |
| `payload` | 任务载荷 |
| `status` | pending/running/completed/failed |
| `priority` | 优先级 |
| `retry_count` / `max_retries` | 重试状态 |
| `last_error` | 最近错误 |
| `created_at` / `started_at` / `completed_at` | 时间戳 |

### `system_settings`

持久化系统配置。

| 字段 | 说明 |
| :--- | :--- |
| `key` | 主键 |
| `value` | JSON 值 |
| `category` | 分类 |
| `description` | 说明 |
| `updated_at` | 更新时间 |

## 分发和推送表

### `distribution_rules`

分发规则表。

| 字段 | 说明 |
| :--- | :--- |
| `id` | 主键 |
| `name` / `description` | 名称和描述 |
| `match_conditions` | 匹配条件 JSON |
| `enabled` / `priority` | 启用状态和优先级 |
| `nsfw_policy` | NSFW 策略 |
| `approval_required` | 是否需要审批 |
| `rate_limit` / `time_window` | 频率限制 |
| `template_id` / `render_config` | 渲染配置 |
| `created_at` / `updated_at` | 时间戳 |

### `distribution_targets`

规则目标表。

| 字段 | 说明 |
| :--- | :--- |
| `id` | 主键 |
| `rule_id` | 关联 `distribution_rules.id` |
| `bot_chat_id` | 关联 `bot_chats.id` |
| `enabled` | 是否启用 |
| `backfill_watermark` | 历史回填水位 |
| `merge_forward` / `use_author_name` | 推送渲染选项 |
| `summary` | 摘要 |
| `render_config_override` | 目标级渲染覆盖 |
| `created_at` / `updated_at` | 时间戳 |

### `content_queue_items`

分发队列表，按 `(content_id, rule_id, bot_chat_id)` 建模。

| 字段 | 说明 |
| :--- | :--- |
| `id` | 主键 |
| `content_id` | 关联 `contents.id` |
| `rule_id` | 关联 `distribution_rules.id` |
| `bot_chat_id` | 关联 `bot_chats.id` |
| `target_platform` / `target_id` | 推送目标 |
| `status` | 队列状态 |
| `priority` / `scheduled_at` | 调度信息 |
| `rendered_payload` / `nsfw_routing_result` | 渲染和 NSFW 路由结果 |
| `passed_rate_limit` / `rate_limit_reason` | 频率限制结果 |
| `approved_by` | 审批人 |
| `attempt_count` / `max_attempts` / `next_attempt_at` | 重试信息 |
| `locked_at` / `locked_by` | worker 锁 |
| `message_id` | 推送消息 ID |
| `last_error*` | 最近错误 |
| `started_at` / `completed_at` / `created_at` / `updated_at` | 时间戳 |

### `pushed_records`

推送记录和去重表。

| 字段 | 说明 |
| :--- | :--- |
| `id` | 主键 |
| `content_id` | 关联 `contents.id` |
| `target_platform` / `target_id` | 目标平台和目标 ID |
| `message_id` | 推送后的消息 ID |
| `push_status` / `error_message` | 推送状态和错误 |
| `pushed_at` | 推送时间 |

## Bot 表

### `bot_configs`

Bot 配置表。

| 字段 | 说明 |
| :--- | :--- |
| `id` | 主键 |
| `platform` | telegram/napcat 等 |
| `name` | 配置名称 |
| `bot_token` | Telegram token |
| `napcat_http_url` / `napcat_ws_url` / `napcat_access_token` | Napcat 配置 |
| `enabled` / `is_primary` | 启用和主配置 |
| `bot_id` / `bot_username` | Bot 身份 |
| `created_at` / `updated_at` | 时间戳 |

### `bot_chats`

Bot 会话/群组表。

| 字段 | 说明 |
| :--- | :--- |
| `id` | 主键 |
| `bot_config_id` | 关联 `bot_configs.id` |
| `chat_id` / `chat_type` | 平台 chat 标识和类型 |
| `title` / `username` / `description` | 群组/频道信息 |
| `member_count` | 成员数 |
| `is_admin` / `can_post` | Bot 权限 |
| `enabled` / `is_monitoring` / `is_push_target` | 功能开关 |
| `nsfw_chat_id` | NSFW 分流目标 |
| `total_pushed` / `last_pushed_at` | 推送统计 |
| `raw_data` | 平台原始数据 |
| `is_accessible` / `last_sync_at` / `sync_error` | 同步状态 |
| `created_at` / `updated_at` | 时间戳 |

### `bot_runtime`

Bot 运行态。

| 字段 | 说明 |
| :--- | :--- |
| `id` | 主键 |
| `platform` | 平台 |
| `bot_id` / `bot_username` / `bot_first_name` | Bot 身份 |
| `started_at` / `last_heartbeat_at` | 运行时间 |
| `version` | 版本 |
| `last_error` / `last_error_at` | 最近错误 |
| `updated_at` | 更新时间 |

## Agent 表

### `agent_sessions`

Agent 会话。

| 字段 | 说明 |
| :--- | :--- |
| `id` | 主键 |
| `title` | 标题 |
| `status` | 会话状态 |
| `context_budget` | 上下文预算 |
| `created_at` / `updated_at` / `last_message_at` / `deleted_at` | 时间戳 |

### `agent_messages`

Agent 消息。

| 字段 | 说明 |
| :--- | :--- |
| `id` | 主键 |
| `session_id` | 关联会话 |
| `run_id` | 关联 run |
| `role` | user/assistant/tool 等角色 |
| `content` | 文本 |
| `payload` | 结构化载荷 |
| `created_at` | 创建时间 |

### `agent_runs`

Agent 运行记录。

| 字段 | 说明 |
| :--- | :--- |
| `id` | 主键 |
| `session_id` | 关联会话 |
| `status` | running/completed/failed 等 |
| `input_message` / `output_message` | 输入和输出 |
| `error_code` / `error_message` | 错误 |
| `usage` | token/模型使用量 |
| `created_at` / `updated_at` / `completed_at` | 时间戳 |

### `agent_tool_calls`

Agent 工具调用。

| 字段 | 说明 |
| :--- | :--- |
| `id` | 主键 |
| `run_id` / `session_id` | 关联 run 和 session |
| `tool_name` | 工具名 |
| `permission_level` | 权限等级 |
| `status` | 调用状态 |
| `args` / `result` / `error` | 参数、结果、错误 |
| `created_at` / `completed_at` | 时间戳 |

### `agent_confirmations`

高风险工具确认。

| 字段 | 说明 |
| :--- | :--- |
| `id` | 主键 |
| `session_id` / `run_id` / `tool_call_id` | 关联对象 |
| `tool_name` | 工具名 |
| `permission_level` | 权限等级 |
| `status` | pending/approved/rejected 等 |
| `args` / `summary` / `result` / `error` | 确认内容和结果 |
| `created_at` / `decided_at` | 时间戳 |

### `agent_context_summaries`

Agent 上下文压缩摘要。

| 字段 | 说明 |
| :--- | :--- |
| `id` | 主键 |
| `session_id` / `run_id` | 关联对象 |
| `summary` | 摘要文本 |
| `covered_message_count` | 覆盖消息数 |
| `token_estimate` | token 估算 |
| `created_at` | 创建时间 |

## FTS5 虚拟表

`contents_fts` 不是 ORM 表，而是 `backend/app/core/database.py` 在 SQLite 中创建的 FTS5 虚拟表。它索引 `contents.title`、`contents.body`、`contents.summary`，并通过触发器跟随 `contents` 插入、更新和删除。

## 当前问题

- API 和数据库文档仍是手写文档，需要定期和 ORM/OpenAPI 校验。
- 历史迁移脚本不再作为本文档基线；如需追溯历史库升级，请查看 git 历史或后续专门的 migration 文档。
