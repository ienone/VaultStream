# Twitter (X) 内容适配器文档

VaultStream 的 Twitter 适配器利用 FxTwitter API 提供了高效的推文解析能力，能够在无需官方 API 密钥或登录的情况下获取公开推文的详尽数据。

---

## 1. 支持的 URL 模式

适配器支持所有主流的 Twitter/X URL 格式：

| 模式 | 示例 |
| :--- | :--- |
| 标准推文 | `https://twitter.com/{user}/status/{id}` |
| 新版域名 | `https://x.com/{user}/status/{id}` |
| 移动端链接 | `https://mobile.twitter.com/{user}/status/{id}` |
| 带参数链接 | `https://x.com/{user}/status/{id}?s=20` |

---

## 2. 解析策略

适配器完全基于 **FxTwitter (FixTweet)** 提供的公开 API。是稳定的第三方方案，用于社交媒体内容的预览和提取。

### 2.1 技术优势

- 无需认证：不需要 Twitter 账号、Cookies 或官方 API Key。
- 绕过反爬：由 FxTwitter 服务端处理 Twitter 的反爬机制和 Cloudflare 验证。
- 完整媒体：自动提取最高画质的图片、原画视频和动态 GIF。
- 结构化数据：返回包含完整统计信息的 JSON，减少了 DOM 解析的脆弱性。

### 2.2 核心接口

- 端点: `https://api.fxtwitter.com/{username}/status/{tweet_id}`
- 方法: `GET`
- 响应: 包含 `tweet` 对象的标准 JSON 数据。

---

## 3. 数据映射与存档

### 3.1 字段映射表

| 字段 | Twitter (Fx) 来源 | 说明 |
| :--- | :--- | :--- |
| `platform` | `twitter` | 常量 |
| `content_type` | `tweet` | 默认为推文类型 |
| `title` | `@user: text[:50]...` | 自动生成的标题预览 |
| `description` | `text` | 原始推文文本 |
| `author_name` | `author.name` | 作者显示名称 |
| `author_id` | `author.screen_name` | 作者用户名 (@ handle) |
| `published_at` | `created_at` | 自动解析 ISO 8601 时间戳 |

### 3.2 互动统计 (stats)

| 统计项 | 说明 |
| :--- | :--- |
| `view` | 浏览次数 (Views) |
| `like` | 点赞数 (Likes) |
| `share` | 转发数 (Retweets) |
| `reply` | 评论/回复数 (Replies) |
| `bookmarks` | 书签保存数 (Bookmarks) |

### 3.3 媒体存档 (Archive)

适配器会为媒体处理模块准备专用的 `archive` 结构：
- 图片：提取 `media.all` 或 `media.photos` 中的所有 URL。
- 视频：提取原画视频链接及相关尺寸信息。
- 引用：支持获取被引用推文 (Quote) 的基本信息。

---

## 4. 回退与故障排查

### 4.1 错误处理逻辑
- 404: `NonRetryableAdapterError`（推文已删除或账号私密）。
- 429: `RetryableAdapterError`（触发 API 频率限制，通常由 FxTwitter 侧触发）。
- 5xx: `RetryableAdapterError`（FxTwitter 服务暂时不可用）。

### 4.2 代理建议
如果服务器在无法直接访问外部 API 的环境下，请确保 `settings.http_proxy` 已正确配置。FxTwitter 本身在海外运行，通常连接非常稳定。

---

## 5. 开发者参考

### 5.1 关键类
- `TwitterFxAdapter`: 位于 `backend/app/adapters/twitter_fx.py`。

### 5.2 注意事项
- 敏感内容：部分标记为“可能包含敏感内容”的推文，FxTwitter 依然可以解析，但请确保前端展示符合规范。
- 媒体处理：如果开启了 `ENABLE_ARCHIVE_MEDIA_PROCESSING`，系统将自动对推文中的图片进行 WebP 转码并存入对象存储。
