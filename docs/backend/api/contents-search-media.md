# API 领域：内容、搜索与媒体

## 文档状态

active

## 事实来源

- Router：`backend/app/routers/contents.py`、`shares.py`、`cards.py`、`search.py`、`media.py`
- Schema：对应 router 使用的 `backend/app/schemas/`
- 前端调用：`frontend/lib/core/api/` 及收藏域 provider

本文只记录跨调用方必须稳定理解的行为。请求字段、枚举和响应结构以 schema 与 OpenAPI 为准。

## 捕获与内容

- `POST /api/v1/shares` 接收分享链接并创建或合并内容。`tags` 与 `tags_text` 会在服务端统一拆分、去空和去重。
- `GET /api/v1/contents` 提供分页、平台、状态、标签、作者、日期、关键词和 NSFW 筛选。
- `GET /api/v1/contents/{content_id}` 返回单条内容详情。
- `PATCH /api/v1/contents/{content_id}` 更新允许人工维护的内容字段。
- `DELETE /api/v1/contents/{content_id}` 删除内容及关联记录；本地媒体只有在没有其他内容引用时才删除物理文件。

内容列表、详情与卡片接口不是三套独立事实源。新增字段时应先确认内容 schema，再决定列表或卡片是否暴露其子集。

## 后处理动作

- `POST /api/v1/contents/{content_id}/re-parse` 调度重新解析，返回可观察的 `run_id`。
- `POST /api/v1/contents/{content_id}/generate-summary` 生成摘要并记录后台运行。
- `POST /api/v1/contents/{content_id}/patrol-score` 仅适用于发现流内容；非发现流内容返回业务错误。
- `GET /api/v1/contents/{content_id}/processing-status` 汇总内容后处理状态，不应被前端当成新的内容详情模型。

后台动作的“已受理”不等于“已经成功”。前端应通过 `run_id`、任务结果接口或事件更新最终状态。

## 搜索与语义索引

- `GET /api/v1/search/semantic` 执行语义/混合检索；结果同时返回 `content_type` 与 `effective_layout_type`，保证搜索卡片和普通收藏卡片采用相同内容模板。
- `GET /api/v1/search/semantic/index-status` 返回索引能力和当前状态。
- `POST /api/v1/search/semantic/reindex` 在 `dry_run=true` 时只估算候选和调用量；实际执行时返回 `run_id`。
- `POST /api/v1/search/semantic/embeddings/{embedding_id}/retry` 重试单个失败分块，并产生 `semantic_reindex` 运行记录。

搜索结果必须保留内容 ID 和匹配来源，便于界面回到存档证据；不能只返回模型生成文本。

## 媒体访问

- 内容详情与分享卡片现在都可返回 `media_assets`，每个资产包含按 `purpose` 排序的 `sources`；列表与详情不另建封面事实源。
- `GET /api/v1/media/assets/{asset_id}/manifest` 使用控制面鉴权刷新一个资产的候选。
- `GET /api/v1/media/blobs/{key}` 使用绑定 storage key、variant ID 和过期时间的资源级签名读取本地对象，不接收全局 API Token。
- `GET /api/v1/media/{key}` 是迁移期间仍供旧 URL 字段使用的受保护端点；统一媒体调用方不得新增对此路径的依赖。
- `GET /api/v1/proxy/image` 代理远程图片，必须遵守后端 URL 安全和缓存策略。
- `local://` 是旧存档引用，不是前端可直接请求的 HTTP URL。新调用方只执行后端返回的 `MediaSource`，不得自行拼接签名或代理 URL。

生产环境必须配置与 `API_TOKEN` 不同的 `MEDIA_SIGNING_SECRET`。签名过期返回稳定错误码 `media_signature_expired`；签名错误、变体不存在和物理 blob 缺失使用各自错误码，前端不得解析错误文案。

媒体失败态和代理访问问题见 `../../issues/media-proxy-image-access.md`。

## 变更检查

- 先读取 router、schema、service 返回值、现有客户端和相关测试。
- API 字段或状态码变化必须同时更新 OpenAPI、前端类型和本分册。
- 不允许在前端通过猜测多个响应形态维持兼容。
