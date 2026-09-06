# 后端模块：内容管理

## 文档状态

active

## 代码位置

- Router: `backend/app/routers/contents.py`
- Service: `backend/app/services/content_service.py`
- Presenter: `backend/app/services/content_presenter.py`
- Repository: `backend/app/repositories/content_repository.py`
- Model/Schema: `backend/app/models/content.py`、`backend/app/schemas/content.py`

## 功能

- 接收分享 URL 或手动内容。
- 调用平台适配器解析内容。
- 存储标题、正文、作者、媒体、统计、标签、状态和 archive metadata。
- 提供内容列表、详情、编辑、删除、重新解析和后处理状态。

## 不承担职责

- 不直接实现平台认证。
- 不直接执行推送分发。
- 不直接持有全局自动化策略；只读取策略结果。

## 实现逻辑

内容创建入口会先规范化 URL、按 `(platform, canonical_url)` 去重并记录 `ContentSource`，再将解析任务写入 SQLite Task 队列。应用内粘贴和系统分享分别记录 `manual_paste` 与 `system_share` 来源，但共享同一 `/shares` contract 和前端写控制层。队列写入失败时，已提交的内容和来源保持为可重试状态，HTTP 返回 `503`、`parse_queue_unavailable` 与 `content_id`；调用方应表达“已保存、解析待处理”，不能把整个捕获动作误报为失败。重复提交同一 URL 复用原内容并再次尝试入队。解析成功后触发摘要、语义索引、媒体归档、审批/分发等后处理。详情返回前会通过 presenter 转换 `local://` 媒体 URL，并补充有效布局类型。

原始文本通过 `POST /captures/text` 直接保存为 `universal/note` 内容：正文是权威原文，状态从 `parse_success` 开始，不伪造外部 URL，也不进入网页解析队列；随后仍复用摘要、语义索引和自动分发后处理。每次文本捕获创建独立内容，不按正文猜测去重。

原始文件通过 `POST /captures/file` 或 `POST /captures/files` 流式写入内容寻址 storage，并创建 ready 的 `MediaAsset` 与 original archive `MediaVariant`。同一次系统分享的多个文件保留在一个内容对象中：多张图片使用 gallery，混合附件使用 document，并按分享顺序保存资产。单文件标题默认取净化后的文件名；多文件使用数量标题，用户说明保存在正文中，分享时间等来源上下文保存在 `ContentSource`。上传链路不等待 OCR 或转码，也不伪造已提取正文。

Telegram Bot 的显式 `/save` 也是该 contract 的生产者：回复图片、文件、音视频或语音时，Bot 先通过 Telegram 文件接口取得原件，再以单项 multipart 调用 `/captures/files`，保留 `telegram_bot` 来源和消息上下文。私聊中严格匹配保存前缀的自然语言请求复用同一处理器；疑问句、其他普通聊天和群聊文本不自动归档。Bot 不自行写内容、媒体表或 storage，也不把已监控 chat 的 discovery 缓冲混入用户主动归档。

平台解析器统一输出 `ParsedContent`，写入边界位于 `tasks/parsing.py`：

- 标题、正文、作者、封面、正文媒体、发布时间、平台 ID、原生类型和布局类型写入对应列。
- `view/like/favorite/share/reply` 映射到五个通用统计列；平台独有统计写入 `extra_stats`。
- 平台话题写入 `source_tags`；引用内容、投票等可展示结构写入 `rich_payload`；原始响应和归档处理输入写入私有 `archive_metadata`。
- 头像可以进入私有归档供本地化，但不得作为正文 `media_urls` 或无媒体内容的封面。
- 生产解析与 `/platform-health/parse-test` 共用 `services/platform_parsing.py` 创建适配器，均读取数据库中扫码登录保存的完整平台 Cookie；Bilibili 仅在数据库未配置时回退到旧环境变量分片。

人工修改的标题、正文、作者、封面、标签和模板记录在 `manual_edit_fields`。后续解析仍会刷新未受保护的事实字段与媒体；受保护字段出现差异时，当前人工值保持不变，最新解析值和时间写入 `parse_candidate`。调用方通过 `/contents/{id}/parse-candidate/resolve` 逐字段选择采用解析值、保留当前值或提交合并值，不允许一次决策顺带处理其他候选。采用解析值会解除该字段的人工保护；保留或合并会继续保护。

删除、解析 retry、摘要生成、巡逻评分和重新解析均使用独立命名 response model。摘要与巡逻评分在 HTTP 返回前已经完成并结算对应 run；重新解析只在响应前创建 run 并加入后台任务。三者都要求返回非空 `run_id`，调用方不得把同步完成和后台受理显示成同一种状态。

## 测试

长期回归与临时验收边界见 [验证策略](../testing.md)。本模块其余行为在变更时针对性验收，不保留逐方法测试清单。

## 与其他模块交互

- adapters: 解析平台内容。
- media: 提取、归档、转换图片和视频。
- search-rag: 写入语义索引。
- distribution: 入库后可进入分发队列。
- events/tasks: 发送内容变化和任务状态。

## 对应前端

- `../../frontend/pages/collection.md`
- `../../frontend/pages/content-detail.md`

## API 接口

详见 `../api.md` 中内容管理 API，包括 `/shares`、`/captures/text`、`/captures/file`、`/contents`、`/contents/{id}`、`/contents/{id}/re-parse`、`/contents/{id}/parse-candidate/resolve` 等。

## 配置与策略

- 解析、摘要、语义索引、媒体归档和分发是否执行应受系统配置和自动化策略约束。
- 内容详情只暴露当前状态，不应绕过后端策略触发外部副作用。

## 当前问题

- 详情后处理面板副作用：`../../issues/frontend-post-processing-panel-side-effects.md`
- 统一任务结果 contract 解决记录：`../../issues/archive/task-run-result-contract-missing.md`
- 媒体代理与图片访问修复记录：`../../issues/archive/media-proxy-image-access.md`

## 尚未实现 / 计划扩展

内容模板、任务结果和媒体体验分别属于系统构想与前端 IA 的目标能力；每个部分开始实施前都要重新核对当前数据模型、API、真实样本和相关 issue。

文件捕获先暂存整批、再统一发布；超限/空文件/读取失败会移除整批暂存，发布失败只回收本次新建且未被提交内容引用的对象。删除事件唯一成员内容返回 409 `knowledge_event_requires_member`，要求先为事件补充另一条内容；与事件成员移除共用事务内约束。
