# 微博内容适配器文档

VaultStream 的微博适配器通过模拟移动端和 Web 端的 AJAX 接口，支持解析博文（Status）和用户主页（User Profile）。

---

## 1. 支持的 URL 模式

适配器支持自动识别、还原并净化以下微博路径：

| 模式 | 示例 |
| :--- | :--- |
| 标准正文页 | `weibo.com/{uid}/{mblogid}` |
| 详情页 | `weibo.com/detail/{mblogid}` |
| 移动端/轻量版 | `m.weibo.cn/status/{mblogid}` |
| 短链接/APP 分享 | `mapp.api.weibo.cn/fx/...` (自动还原) |
| 用户主页 | `weibo.com/u/{uid}` |

---

## 2. 解析策略

微博的 API 环境较为复杂。我们采用了“访客模式优先 + 移动端还原”的策略。

### 2.1 核心接口

| 类型 | API 端点 | 说明 |
| :--- | :--- | :--- |
| 博文详情 | `ajax/statuses/show` | 主力接口，获取完整的推文文本、媒体列表和互动统计 |
| 长文获取 | `ajax/statuses/longtext` | 针对 `isLongText=true` 的博文，获取被折叠的完整内容 |
| 用户信息 | `ajax/profile/info` | 获取博主头像、昵称、粉丝数等元数据 |

### 2.2 自动链路还原
针对来源不明的 `mapp.api.weibo.cn` 等 APP 分享链接，适配器会自动：
1. 发起带移动端 User-Agent 的请求。
2. 捕获重定向后的真实 Bid/Mblogid。
3. 转换为标准详情页链接进行解析。

---

## 3. 数据映射与统计

### 3.1 字段提取

| 字段 | 来源 | 说明 |
| :--- | :--- | :--- |
| `platform_id` | `mblogid` | 字符串 ID (如 QmsEAti7w) |
| `description` | `text` | 已自动补全长文，并剥离 HTML 标签 |
| `author_name` | `user.screen_name` | 用户昵称 |
| `published_at` | `created_at` | 自动处理微博特有的时间格式 |
| `cover_url` | `pic_infos` / `page_pic` | 自动选择原图或高清封面 |

### 3.2 互动统计 (stats)

| 统计项 | 对应微博字段 |
| :--- | :--- |
| `like` | `attitudes_count` |
| `reply` | `comments_count` |
| `repost` | `reposts_count` |
| `share` | `reposts_count` (映射为共享字段) |

---

## 4. 媒体处理逻辑

微博图片存在多级分辨率。适配器按照以下优先级提取：
1. `mw2000` (最高清/2000px 宽度)
2. `largest`
3. `original`

对于视频，适配器会尝试从 `page_info` 或 `mix_media_info` 中提取最高分辨率的 MP4 链接。

---

## 5. 配置与限制

### 5.1 Cookie 配置
虽然部分博文支持访客模式，但若要解析受限内容或提高稳定性，建议配置 Cookie。

```env
# .env 文件
WEIBO_COOKIE=\"SUB=...; _s_tentry=...;\"
```

### 5.2 访问限制
- 私密博文或仅好友可见博文无法解析。

---

## 6 扩展建议
- “超话”内容和“微栏目”等特殊识别有待实现。
