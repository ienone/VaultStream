# 数据库领域：内容、来源与搜索

## 文档状态

active

## ORM 来源

- `backend/app/models/content.py`
- `backend/app/models/search.py`

## `contents`

`contents` 是存档内容的核心事实表。字段按职责分组：

| 职责 | 主要字段 |
| :--- | :--- |
| 身份与去重 | `platform`、`url`、`canonical_url`、`clean_url`、`platform_id` |
| 解析与人工状态 | `status`、`failure_count`、`last_error*`、`review_status`、`reviewed_*` |
| 展示语义 | `layout_type`、`layout_type_override`、`content_type`、`title`、`body`、`summary` |
| 作者与媒体 | `author_*`、`cover_url`、`cover_color`、`media_urls` |
| 来源与标签 | `source`、`source_type`、`tags`、`source_tags`、`context_data` |
| AI 与发现 | `ai_score`、`ai_reason`、`ai_tags`、`discovery_state`、`discovered_at`、`expire_at`、`promoted_at` |
| 结构化存档 | `rich_payload`、`archive_metadata`、`extra_stats` |
| 关系与时间 | `parent_id`、`is_synthesis`、`deleted_at`、`created_at`、`updated_at`、`published_at` |

`layout_type` 是当前渲染分类，不应被解释为完整的长期模板体系；平台原生类型保留在 `content_type` 和结构化 payload 中。

## `media_assets` 与 `media_variants`

统一媒体模型已建立独立的资产与变体表：

- `media_assets` 保存内容归属、媒体类型、业务角色、顺序、原始来源、归档状态和客户端直连策略。
- `media_variants` 保存本地 storage key、变体类型、格式/编解码信息、尺寸、状态和校验值。
- API 返回的短期签名 URL 与代理 URL 不入库，由 manifest service 按用途生成。

现有内容数据尚未完成回填，`cover_url`、`author_avatar_url`、`media_urls` 和 `archive_metadata` 当前仍是迁移输入；不得在新代码中将这些旧字段当作媒体资产表的等价事实。

## 来源与发现

- `content_sources` 保存每次分享或导入的来源、标签快照、备注和客户端上下文。一条内容可以有多个来源记录。
- `discovery_sources` 保存来源类型、配置、启用状态、同步间隔、cursor 和最近错误。
- `content_discovery_links` 记录内容与发现源之间的关联，不替代内容的规范 URL。

重复内容合并时应保留新的来源记录，不能因为主体内容已存在就丢失转发说明或捕获渠道。

## `content_embeddings`

语义索引按内容和分块保存：

- `chunk_index=-1` 表示全文或摘要级索引，非负值表示正文分块。
- 模型身份由 `embedding_model` 与 `embedding_model_signature` 共同描述。
- `text_hash` 用于判断输入是否变化。
- `index_status`、`failure_reason`、`retry_count`、`last_attempted_at` 和 `last_indexed_at` 描述索引生命周期。
- `source_text` 用于检索解释和证据回溯。

当前向量保存为 SQLite JSON，尚未依赖 sqlite-vec 或 sqlite-vss。这个实现事实不应被写成长期方案承诺。

## FTS5

`contents_fts` 由 `backend/app/core/database.py` 在运行期创建，索引标题、正文和摘要，并通过触发器跟随内容插入、更新和删除。它不是 ORM 表，结构校验时必须单独检查。

## 关键一致性

- 内容删除时，来源、发现关联、语义索引和分发引用必须按各自外键/服务规则处理。
- 本地媒体引用删除前必须检查是否仍被其他内容使用。
- FTS 行数和内容表活跃记录数出现异常差异时，应先修复索引而不是在查询侧静默兼容。
