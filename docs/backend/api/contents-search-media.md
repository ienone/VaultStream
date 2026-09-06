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
- `/shares` 成功响应包含可直接进入详情的内容 `id`。若内容和来源已经保存但解析任务入队失败，响应为 `503 parse_queue_unavailable` 并带 `content_id`；这是捕获成功后的待处理状态，不是数据回滚。
- `POST /api/v1/captures/text` 接收原始文本、可选标题、标签和来源。正文直接保存为 `parse_success` 的 `universal/note` 内容，不调用网页适配器；标题留空时使用正文第一条非空行。摘要和语义索引仍是后处理结果，不得覆盖或冒充原文。
- `POST /api/v1/captures/file` 接收 `multipart/form-data` 原始文件，以及可选标题、标签、说明和 NSFW 标记。服务端边接收边计算 SHA-256，写入仓库配置的本地 storage，并以统一 `MediaAsset` / 原始 `MediaVariant` 暴露签名访问；图片、视频、音频和文档使用明确的内容类型，不经过网页适配器。空文件返回 `400 capture_file_empty`，超过 `CAPTURE_UPLOAD_MAX_BYTES`（默认 512 MiB）返回 `413 capture_file_too_large`。
- `POST /api/v1/captures/files` 接收同一次分享中的 1–32 个 `uploads`。所有文件归入同一个内容对象并按顺序建立独立 `MediaAsset`；多张图片形成 gallery，其他混合文件形成带附件的 document。单个文件仍受 `CAPTURE_UPLOAD_MAX_BYTES` 限制；来源说明和 `client_context_json` 写入同一条 `ContentSource`，无效上下文返回稳定错误码。
- `GET /api/v1/contents` 提供分页、平台、状态、标签、作者、日期、关键词和 NSFW 筛选。
- `GET /api/v1/contents/{content_id}` 返回单条内容详情。若 `rich_payload.chunks[]` 含显式章节/转写时间点，响应会额外返回经过媒体归属、类型和时长校验的 `media_segments`；调用方不应自行解析原始 payload 猜测可播放位置。
- `GET, POST /api/v1/contents/{content_id}/media-bookmarks` 按明确 `media_asset_id` 列出或创建用户时间点书签；`PATCH, DELETE /api/v1/contents/{content_id}/media-bookmarks/{bookmark_id}` 编辑可选笔记或删除书签。服务端验证内容存在、资产归属、audio/video 类型、非负秒数和已知媒体时长；同一资产的同一毫秒位置只保留一个书签。
- `PATCH /api/v1/contents/{content_id}` 更新允许人工维护的内容字段。只有值实际变化的标题、正文、作者、封面、标签和模板会记为人工修订；`layout_type_override=null` 会恢复自动模板并解除对应保护。
- `POST /api/v1/contents/{content_id}/parse-candidate/resolve` 逐字段处理重新解析候选。`accept_parsed` 采用新解析并解除该字段保护，`keep_current` 保留人工值，`merge` 必须提交 `merged_value` 并继续保护合并值。不存在对应候选时返回 `409`。
- `DELETE /api/v1/contents/{content_id}` 删除内容及关联记录并返回 `ContentDeleteResponse`；本地媒体只有在没有其他内容引用时才删除物理文件。

内容列表、详情与卡片接口不是三套独立事实源。新增字段时应先确认内容 schema，再决定列表或卡片是否暴露其子集。

## 后处理动作

- `POST /api/v1/contents/{content_id}/retry` 同步执行解析重试，成功时返回内容最新状态；它不是后台受理 contract。
- `POST /api/v1/contents/{content_id}/re-parse` 创建可观察 run 并调度后台重新解析，`ContentReparseAcceptedResponse` 的 `processing` 只表示已受理。人工修订字段不会被解析器静默覆盖；差异写入详情的 `parse_candidate.fields`，并保留最新候选时间。
- `POST /api/v1/contents/{content_id}/generate-summary` 在响应前完成摘要生成并结算 run，返回摘要与 `run_id`。
- `POST /api/v1/contents/{content_id}/patrol-score` 在响应前完成评分并结算 run，仅适用于发现流内容；非发现流内容返回业务错误。
- `GET /api/v1/contents/{content_id}/processing-status` 汇总内容后处理状态，不应被前端当成新的内容详情模型。

后台动作的“已受理”不等于“已经成功”。前端必须按具体 response model 区分同步完成与异步受理，并保留 `run_id` 供任务详情追踪。

## 搜索与语义索引

- `GET /api/v1/search/semantic` 执行语义/混合检索；结果同时返回 `content_type` 与 `effective_layout_type`，保证搜索卡片和普通收藏卡片采用相同内容模板。
- `GET /api/v1/search/unified` 按 `kind=all|contents|events|people|topics|timepoints` 分组返回内容、人工知识事件和结构化导航结果。`content_scope=library|discovery|all` 约束内容及其派生结果，不影响事件。内容保留 `fts|vector|hybrid`，事件保留 `title|description|member` 匹配来源，调用方不得把两种检索解释成同一语义能力。
- `people` 从混合检索命中及 `author_name` 精确字段召回的内容聚合，`topics` 从混合检索命中及 `tags` 精确字段召回的内容聚合；精确字段召回不依赖 embedding。二者返回命中内容数和最近内容 ID，调用方应进入内容筛选，不得假设存在独立人物/主题实体。
- `timepoints` 只接受 `rich_payload.chunks[]` 上单一显式 contract：`segment_type=chapter|transcript`、同内容的音频/视频 `media_asset_id`、非负 `start_seconds`，以及可选且大于起点的 `end_seconds`。响应保留内容/资产 ID、媒体与片段类型、标题、摘录、秒数、匹配来源和分数。发布日期、媒体总时长、无效资产与越界秒数均不会转成时间点。
- `GET /api/v1/search/semantic/index-status` 返回索引能力和当前状态。
- `POST /api/v1/search/semantic/reindex` 在 `dry_run=true` 时只估算候选和调用量；实际执行时返回 `run_id`。
- `POST /api/v1/search/semantic/embeddings/{embedding_id}/retry` 同步重试单个失败分块，返回命名结果及必需 `run_id`，并结算对应 `semantic_reindex` 运行记录。

搜索结果必须保留内容 ID 和匹配来源，时间点还必须保留媒体资产 ID 与显式秒数，便于界面回到存档证据；不能只返回模型生成文本。

## 媒体访问

- 内容详情与分享卡片现在都可返回 `media_assets`，每个资产包含按 `purpose` 排序的 `sources`；列表与详情不另建封面事实源。
- 用户上传原件与平台归档媒体共享同一内容寻址存储和签名读取 contract；文件名、MIME、大小和校验和是资产 metadata，不参与物理路径拼接。
- `GET /api/v1/media/assets/{asset_id}/manifest` 使用控制面鉴权刷新一个资产的候选。
- 本地签名来源包含独立 `variant_id`。`POST /api/v1/media/assets/{asset_id}/failures` 接收该变体 ID 与稳定失败码；服务端重新核对变体归属、物理文件及图片可解码性后才把变体标记为 `missing`/`failed`，不直接信任客户端观察。
- `GET /api/v1/media/blobs/{key}` 使用绑定 storage key、variant ID 和过期时间的资源级签名读取本地对象，不接收全局 API Token。
- `GET /api/v1/media/{key}` 是迁移期间仍供旧 URL 字段使用的受保护端点；统一媒体调用方不得新增对此路径的依赖。
- `GET /api/v1/proxy/image` 代理远程图片，必须遵守后端 URL 安全和缓存策略。
- 图片代理缓存命中按缓存对象实际 MIME 返回；冷请求的 `X-Cache-Persist` 表达缓存持久化结果，`X-Proxy-Warning` 表达转码降级。调用方不得把图片响应成功误解为缓存也已成功。
- 同 URL 的并发冷请求共享 URL hash 临界区并在锁内复查缓存；不同 URL 的冷下载和解码链路最多并发 4 路。
- `local://` 是旧存档引用，不是前端可直接请求的 HTTP URL。新调用方只执行后端返回的 `MediaSource`，不得自行拼接签名或代理 URL。

生产环境必须配置与 `API_TOKEN` 不同的 `MEDIA_SIGNING_SECRET`。签名过期返回稳定错误码 `media_signature_expired`；签名错误、变体不存在和物理 blob 缺失使用各自错误码，前端不得解析错误文案。

统一图片与播放器持有完整资产/来源 DTO。签名候选已到期或收到 410 时，每个资产只自动刷新一次 manifest；403 不刷新，404 本地来源会提交服务端核验。音视频首先请求 `purpose=playback` 的候选，并在运行期切换来源时恢复已知播放位置。

播放书签是独立持久事实，不写回解析器拥有的 `rich_payload`，也不复用内容捕获备注或知识事件成员说明。删除内容或媒体资产时由外键级联清理对应书签。

媒体失败态和代理访问修复记录见 `../../issues/archive/media-proxy-image-access.md`。

## 变更检查

- 先读取 router、schema、service 返回值、现有客户端和相关测试。
- API 字段或状态码变化必须同时更新 OpenAPI、前端类型和本分册。
- 不允许在前端通过猜测多个响应形态维持兼容。
