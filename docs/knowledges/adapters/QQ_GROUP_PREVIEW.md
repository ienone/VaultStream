# QQ 群链接预览

## 文档状态

active

Koishi 调用 `POST /api/v1/bot/qq/{config_id}/preview`，使用现有 API Token 鉴权。请求包含 `group_id`、`user_id`、`message_id`、`urls`（1–20 条）和 `reserve_send`（默认 true）。只允许启用的 QQ BotConfig 与 `qq_bot_agent.group_ids` 中的群，默认群为 `1070760473`；已有 BotChat 的 enabled 开关同样生效。

后端返回 `duplicate` 和逐项 `items`。每项 `status` 为 `parsed`、`unsupported` 或 `failed`，携带实际解析得到的 `title/body/author/url/platform/content_type/media_urls`。`text` 复用正式推送的短内容格式，长正文是节选，没有伪造 AI 摘要；`image_url` 至多一张正文图片或封面，不使用头像补图。缺失字段为 null。预览直接使用本次 ParsedContent，不创建 Content、任务、归档、摘要或分发，不查收藏库。

只有 `send_allowed=true` 的项可回群。Koishi 应将 `text` 和可选的 `image_url` 组成一条消息，不为每个媒体单独发消息。服务端已通过 `qq_policy.reserve_group_send` 为每项占用一次额度，与自动推送共用小时限频；发送失败也消耗额度。`reserve_send=false` 用于只读验收，不领取消息、不预留额度，所有项的 `send_allowed` 均为 false。

消息通过 SystemSetting 中按 Bot/群隔离的运行记录去重，每群最多保留 500 个、24 小时内的消息 ID 指纹，不保留 URL 或正文。先领取后解析，重复返回 `duplicate=true, items=[]`。服务中断或发送结果未知时不自动重发；这只保证重报抑制，不表示 QQ 已送达。上线时关闭对应群旧 HTTP 收录监控，避免两条入口同时处理。

## 专用解析范围

能力识别位于 `services/parse_capabilities.py`，严格检查 URL 的真实 hostname、路径及对象 ID，不按整条 URL 的字符串猜平台。

- 微博：状态、用户主页，以及可还原为这些对象的官方 APP 分享链接。
- X：单条 status 链接（含图片、视频定位后缀）。
- 小红书：笔记和用户主页；官方 xhslink 短链安全还原，保留访问 token，并重新检查目标域名和内容类型。
- 知乎：回答、文章、问题、想法、用户、专栏和收藏夹。
- Telegram：公开频道中的单条消息；私有 `/c/`、邀请和频道首页不处理。

Bilibili（含 b23）无条件排除，其余排除项仍读取 `qq_chat_policies.excluded_parse_platforms`。不调用 universal，也不探测任意短链。RSS/Atom feed 不当作文章预览：现有 RSS parse 取的是源的最新条目，不一定是用户分享的目标。

微博、X、小红书和知乎适配器使用 `public_only=true`：不读取数据库或环境变量中的个人 Cookie，不把管理员可见但群成员不可公开读取的内容带入群。匿名访问被平台拒绝时返回 failed，不借用账号补读。专用解析器存在仅表示有解析实现，不保证平台匿名访问永远可用。

单项解析最长 45 秒、最多 4 项并行，调用方为 20 条的完整批次保留 300 秒 HTTP 超时。不支持的链接不回群；失败结果使用固定失败说明，不回传平台内部响应或访问凭据。
