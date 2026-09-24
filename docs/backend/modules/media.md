# 后端模块：媒体处理

## 文档状态

active

## 代码位置

- Router: `backend/app/routers/media.py`
- Processor: `backend/app/media/processor.py`
- References: `backend/app/media/references.py`
- Extractor: `backend/app/media/extractor.py`
- Color: `backend/app/media/color.py`
- Safe fetch: `backend/app/core/safe_fetch.py`
- Storage: `backend/app/adapters/storage/manager.py`

## 功能

- 服务本地 `local://` 媒体。
- 提供 `/media/{key}` 本地媒体读取。
- 提供统一媒体资产 manifest 与资源级签名 blob 读取。
- 从内容结构化 payload 中生成经过资产归属与时长校验的章节/转写导航。
- 持久化用户创建的音视频时间点书签和可选笔记。
- 核验客户端观察到的本地媒体缺失/解码失败，再更新变体修复状态。
- 提供 `/proxy/image` 外链图片代理。
- 处理归档图片 WebP 转码、缩略图、视频存储、封面主色提取。
- 对远程抓取执行 SSRF 和 Content-Type 限制。

## 不承担职责

- 不决定内容是否应该被推送。
- 不承担平台登录。
- `/proxy/image` 不应承担后台归档任务的全部职责。

## 实现逻辑

图片归档只保存一个主文件。Pillow 统一编码，按配置质量生成 WebP；已有 WebP 不再次有损编码，转换后未变小时直接保存已验证的源图，不额外保留另一份原图。缩略图只服务现有列表：主图不超过 300×300 时复用主文件，其余缩略图也按内容哈希存储。转码、缩略图和主色处理在线程中执行。

图片和视频共用下载、去重、存储和结果发布流程。批处理只编排来源分组、复用/下载和引用回写，转换落盘与缩略图处理各自独立。同批相同 URL 只下载处理一次，任一条目有可用本地主文件即可复用；只对网络异常、429 和 5xx 重试，不因解码或落盘失败重复下载。请求保留 URL 中原有的百分号编码，代理不再对框架已解码的 query 参数二次反解。

本地对象使用每次写入独立的临时文件原子发布，写入成功后才更新本地引用。再次处理时检查已有主文件，缺失则重新下载；缩略图缺失时从已有主文件重建。归档处理结果只写回 images/videos 原条目，已删除 stored_images/stored_videos 重复索引及运行时合并分支；旧索引由 Alembic 数据迁移一次性合入原条目。解析与发现入库共用引用更新，只逐项替换成功地址，保留未归档图片和视频。

媒体归档任务会从 archive metadata 中提取图片/视频 URL，下载后写入本地 storage，并同步创建统一资产与变体。内容列表、详情和 manifest 根据当前请求 origin（或显式 `storage_public_base_url`）生成资源级签名 URL，避免把实际运行在 `8008` 的媒体错误指向配置中的控制面 `8000`。

构建资产时，同一类型和角色同时按原始 URL 与全部变体 storage key 去重。归档记录中的远端原图和内容字段中的本地封面/头像引用，只要共享明确的变体键，就属于同一资产，避免图集重复封面。

完整重解析现在按明确的平台媒体身份、原 URL 或本地变体键复用唯一匹配资产，保留其数据库 ID 与用户书签；不按列表位置猜测。相同种类、相同存储键的变体也保留 ID。解析结果没有重新提供某种本地变体时保留已归档版本，关闭归档不清除既有本地媒体。真实移除的资产仍按既有删除语义清理。Bilibili 使用 bvid + cid 作为 source_identity，CDN 签名变化不改变媒体身份；入库时将时间片的 source_identity 明确绑定到同内容资产 ID，不能跨内容引用。

新解析和发现内容入库的媒体处理读取持久化的归档总开关及图片/视频子开关。当前 `PARSE_SUCCESS` 内容再次进入非 force 的普通解析入口会直接跳过，不会补齐缺失媒体；此前文档对自动补处理的描述与代码不符。本地失败上报只核验并标记 repairable，尚不执行补齐任务。关闭某一媒体类型只跳过后续下载，不删除已归档资产，也不抢占已经开始的单项下载。

用户文件捕获直接把上传流写入 storage 下的 `.incoming`，计算 SHA-256 后原子移动到内容寻址路径；相同字节复用同一个物理对象。数据库记录保留原文件名、MIME、大小和校验和，调用方只使用 manifest 返回的签名 URL，不接触物理路径。

删除内容时同时读取旧 `local://` 引用和统一 `MediaVariant.storage_key`。数据库关系先删除并提交，再检查剩余内容及媒体变体引用；只有不再被任何内容使用的对象才从 storage 删除，避免内容寻址去重文件被提前清理。

卡片优先使用当前封面资产，同角色内优先 ready 本地变体。手动修改封面或采纳解析候选时，在同一事务调整封面角色，保留其他资产及变体；旧归档中的 cover 标记不能覆盖当前选择。

内容详情的 `media_segments` 与全局搜索时间点复用同一个解析器。只有显式关联当前内容 audio/video 资产、包含合法起止秒数且未越过已知时长的 `chapter` / `transcript` 切片才进入稳定 contract；发布日期、推断时间和跨内容资产不会进入播放器导航。

切片保留短预览 excerpt 与未经预览截断的 full_text；完整原文与预览通过相同的归属、类型和时间校验，详情逐字稿阅读不能用 280 字预览代替全文。

播放书签存入独立 `media_bookmarks` 表。创建时服务层重新核对内容、媒体资产归属、audio/video 类型和已知时长；同一资产同一毫秒位置不重复创建。笔记可为空，更新只修改用户笔记，不改写解析得到的章节/逐字稿。内容或资产删除时由外键级联清理。

书签删除返回命名 `MediaBookmarkDeleteResponse`，明确删除的书签与内容 ID；前端仍以重新读取书签列表作为显示事实，不从匿名响应猜测对象。

`/proxy/image` 的像素校验、Pillow 解码/转码和缓存目录读取不在事件循环内执行。同 URL 的冷请求按 URL hash 合并，等待者在锁内复查缓存；不同 URL 的冷下载、校验和解码/转码最多同时运行 4 路。配额在进程首次成功写入以及其后每 16 次成功写入检查一次，不再让每个冷请求全量扫描目录。缓存命中根据实际文件扩展名返回 MIME；冷请求用 `X-Cache-Persist` 区分 `stored`、`write-failed`、`quota-failed` 与 `unsupported-mime`，转码失败的原图响应另带 `X-Proxy-Warning: transcode-failed`。缓存是可选加速层，缓存写入失败不应把已经验证并转码完成的图片改写成另一种响应格式。

## 测试

长期回归与临时验收边界见 [验证策略](../testing.md)。本模块其余行为在变更时针对性验收，不保留逐方法测试清单。

## 与其他模块交互

- contents: 内容详情和列表需要媒体 URL。
- distribution: 推送服务读取缩略图和媒体。
- config-system: 媒体归档开关、质量、数量限制来自系统配置。

## 对应前端

- `../../frontend/components/media-rendering.md`
- `../../frontend/pages/content-detail.md`
- `../../frontend/pages/collection.md`

## API 接口

- `GET /api/v1/media/assets/{asset_id}/manifest`
- `POST /api/v1/media/assets/{asset_id}/failures`
- `GET, POST /api/v1/contents/{content_id}/media-bookmarks`
- `PATCH, DELETE /api/v1/contents/{content_id}/media-bookmarks/{bookmark_id}`
- `GET /api/v1/media/blobs/{key}`
- `GET /api/v1/media/{key}`
- `GET /api/v1/proxy/image?url=...`

## 配置与策略

- `enable_archive_media_processing`
- `enable_archive_image_processing`
- `enable_archive_video_processing`
- `archive_image_webp_quality`
- `archive_image_max_count`
- `archive_video_max_count`
- `archive_video_max_bytes`
- `capture_upload_max_bytes`（默认 512 MiB）

## 当前问题

- [图片归档与缓存残留问题](../../issues/2026-09-19-media-localization-integrity.md)：下载、压缩、原子发布与引用更新已收敛；自动补齐触发和客户端缓存身份仍待处理。
- [已关闭问题的历史决策](../../issues/archive/README.md)。
- 统一资产表、签名访问、解析后写入和旧数据回填已建立；代理 MIME/错误阶段、事件循环阻塞边界、冷请求并发和低频配额已收敛；前端嵌套内容、队列预览及后端 Telegram/QQ 分发 payload 已迁移。前端资产图片会单次刷新过期 manifest，本地 404 会触发服务端核验；签名 blob 的 Range 回归已覆盖。仓库实验数据库/存储的真实 FastAPI 探针已依次得到 Range 206、过期 410、刷新后完整读取 200，并把实际缺失变体从 ready 校正为 missing/repairable。真实平台媒体发送以及浏览器/原生端长音视频播放与后台恢复仍未验收。

## 尚未实现 / 计划扩展

图片可达性和完整富媒体归档都是系统构想中的目标能力；何时实施由用户选择的当前功能切片决定，开始前重新核对真实样本、存储策略和平台能力。

## PDF 原生文本边界（2026-09-10）

PDF 读取只接受当前内容所属 document 资产的 ready original_archive/application/pdf 变体，校验 storage 根目录与文件快照 SHA-256。独立子进程最多并发 2 个，单文件上限 64 MiB、500 页、200 万字符、60 秒。保存前再次核对内容版本与变体身份；源改变时撤销整批结果。document_text 内部来源元数据不进入 manifest，文档 DTO 通过独立接口提供。空白/仅图像页保留页码与空文本，不能标为已 OCR。

归档落库时删除与当前正文完全相同的文本副本，以及归档中完全相同的多种文本表示；不同的来源文本仍保留。资产重新排序先腾空旧位置，再复用身份和写入新位置，避免封面切换触发唯一键冲突。
