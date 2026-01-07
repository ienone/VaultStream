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
| `status` | Enum | 状态机: `unprocessed`, `processing`, `pulled`, `distributed`, `failed` |
| `tags` | JSON | 用户自定义标签列表 `["Tech", "Meme"]` |
| `is_nsfw` | Boolean | 是否为敏感内容 |
| `source` | String | 来源标识 (如 `web_test`, `ios_shortcut`) |
| 通用元数据 | | |
| `title` | Text | 标题 |
| `description` | Text | 简介/正文 |
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
| `raw_metadata` | JSON | 原始 API 返回的完整 JSON 报文 |
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

迁移：使用仓库内的 SQL 迁移脚本执行（位于 `backend/migrations/`）。例如：

```bash
cd backend
sqlite3 data/vaultstream.db < migrations/m4_distribution_and_review.sql
```

## 4. 索引 (M3)

### 复合索引
针对管理端的常用查询路径，建立了以下索引：
- `(platform, created_at)`: 按平台和时间排序。
- `(status, created_at)`: 按状态（如“待处理”）和时间排序。
- `(is_nsfw, created_at)`: 按敏感分级和时间排序。

### 全文搜索 (FTS5)
针对 SQLite 平台，利用 `FTS5` 扩展创建了虚拟表 `contents_fts`，并配置了自动化触发器。
- **搜索范围**: 标题 (`title`)、正文描述 (`description`)、作者昵称 (`author_name`)。
- **同步机制**: 采用数据库级触发器 (`AFTER INSERT/UPDATE/DELETE`) 保证搜索索引与 `contents` 原表实时一致。

## 5. 任务队列表 (`tasks`)

由于后端移除了 Redis 依赖，采用 SQLite 表模拟简单的任务队列。支持原子取任务 (`SELECT FOR UPDATE SKIP LOCKED` 语义在 SQLite 中通过文件锁实现并发安全)。

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `id` | Integer | 自增主键 |
| `task_type` | String | 任务类型 (如 `parse_content`) |
| `payload` | JSON | 任务负载 (如 `{"content_id": 123}`) |
| `status` | Enum | `pending`, `running`, `completed`, `failed` |
| `priority` | Integer | 优先级 (越大越靠前) |
| `retry_count`| Integer | 已重试次数 |


## 2. `pushed_records` 表 (分发追踪)

用于实现“推过不再发”逻辑。

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `id` | Integer | 主键 |
| `content_id` | Integer | 外键，关联 `contents.id` |
| `target_platform` | String | 目标平台标识 (如 `TG_CHANNEL_A`) |
| `message_id` | String | 推送成功后的消息 ID (用于后续更新或撤回) |
| `pushed_at` | DateTime | 推送时间 |
