# 数据库结构说明

## 1. `contents` 表 (核心内容存储)

采用“通用字段 + 平台特有字段 (JSON)”的混合存储模式，兼顾查询效率与扩展性。

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `id` | Integer | 自增主键 |
| `platform` | Enum | 平台标识 (`bilibili`, `twitter`, `xiaohongshu` 等) |
| `platform_id` | String | 平台原生 ID (如 B 站 BV 号、推文 ID) |
| `url` | Text | 原始提交链接 |
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
| `like_count` | Integer | 点赞数 |
| `collect_count` | Integer | 收藏数 |
| `share_count` | Integer | 分享数 |
| `comment_count` | Integer | 评论数 |
| 扩展数据 | | |
| `extra_stats` | JSON | 平台特有数据 (如 B 站投币 `coin`、弹幕 `danmaku`) |
| `raw_metadata` | JSON | 原始 API 返回的完整 JSON 报文 |
| 时间戳 | | |
| `published_at` | DateTime | 内容在原平台的发布时间 |
| `created_at` | DateTime | 记录创建时间 |

## 2. `pushed_records` 表 (分发追踪)

用于实现“推过不再发”逻辑。

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `id` | Integer | 主键 |
| `content_id` | Integer | 外键，关联 `contents.id` |
| `target_platform` | String | 目标平台标识 (如 `TG_CHANNEL_A`) |
| `message_id` | String | 推送成功后的消息 ID (用于后续更新或撤回) |
| `pushed_at` | DateTime | 推送时间 |
