# QQ 链接解析与呈现

## 文档状态

active

小 i 在 QQ 私聊及群 1081948298 提取受支持平台链接和 JSON 分享卡片，只触发现有 Agent loop，不提前解析或按关键词决定收藏。模型调用 vaultstream_parse，选择真实当前/引用/本会话材料中的链接和 full、summary、text；普通分享默认 full，不收藏。管理员当前明确收藏才调用保存工具，save_instruction 必须逐字来自当前外层消息。程序继续核验真实身份、会话范围、材料归属和写入开关，不新增意图分类模型。

`POST /api/v1/bot/qq/{config_id}/preview` 使用 API Token。请求：bot_id、chat_id、private、user_id、message_id、request_text、urls（1–20）、format（默认 full）、allow_cleaning（默认 false）、parse_instruction（默认空）。仅管理员当前明确解析、parse_instruction 是外层原话时可用清洗兜底；否则专用解析器失败不会自动清洗。主 Bot 身份、私聊目标与发送者一致、群白名单及 enabled 开关必须满足。

响应为 duplicate 和 items，每项含 url、status、text、message_id；status 为 sent、unsupported、failed、delivery_unknown、rate_limited。发送由后端 NapCat 完成，小 i 不重复发送正文；工具回传只保留回执，实际正文记录于当前会话。消息指纹持久去重，发送未知不自动重试；群发送共用小时频率限制。

full 保留解析取得的正文及图片，长段落按 1500 字符分节点而非截断；text 保留正文、不附媒体；summary 使用约 500 字符节选及最多一张图。B站视频、番剧、直播是单条封面与简介，简介最多 500 字；其他平台混合视频和图片时保留实际图片，不发送视频。文章保留段落和配图分组；首次正文节点有标签，续段不重复，标题/作者/统计/原链接集中于首节点。

一节点直接图文发送，多节点合并转发，每包最多 99 节点，不静默切掉后续节点。封面 source 与节点昵称使用真实 Bot 名字，不生成内容标题摘要。私聊转发遇到 NapCat 已上传资源但未返回回执的特定错误时，只用错误中的 res_id 回读同一私聊、同一 Bot 的完全匹配卡片；找不到则保留结果未知，绝不重发。

解析不创建 Content、ContentSource、媒体资产或队列任务，图片仅在内存读取用于上传。其他群不开放新能力。独立 B站插件保留其他群原功能，但排除 QQ 私聊和群 1081948298，避免重复回复。
