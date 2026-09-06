# 后端模块：媒体处理

## 文档状态

active

## 代码位置

- Router: `backend/app/routers/media.py`
- Processor: `backend/app/media/processor.py`
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

媒体归档任务会从 archive metadata 中提取图片/视频 URL，下载后写入本地 storage，并同步创建统一资产与变体。内容列表、详情和 manifest 根据当前请求 origin（或显式 `storage_public_base_url`）生成资源级签名 URL，避免把实际运行在 `8008` 的媒体错误指向配置中的控制面 `8000`。

新解析、已解析内容补处理和发现内容入库都会读取持久化的媒体归档总开关及图片/视频子开关。`PARSE_SUCCESS` 内容再次进入普通解析入口时不会重复抓取正文，但会检查按策略启用且仍缺少 `stored_key` 的图片和视频；补处理产生的 archive metadata 与本地媒体 URL 会一起提交。关闭某一媒体类型只跳过该类型的后续下载，不删除已归档资产，也不抢占已经开始的单项下载。

用户文件捕获直接把上传流写入 storage 下的 `.incoming`，计算 SHA-256 后原子移动到内容寻址路径；相同字节复用同一个物理对象。数据库记录保留原文件名、MIME、大小和校验和，调用方只使用 manifest 返回的签名 URL，不接触物理路径。

删除内容时同时读取旧 `local://` 引用和统一 `MediaVariant.storage_key`。数据库关系先删除并提交，再检查剩余内容及媒体变体引用；只有不再被任何内容使用的对象才从 storage 删除，避免内容寻址去重文件被提前清理。

卡片用途先返回存在 ready 本地变体的图片资产，再返回仅远端的封面；前端不需要等待不可达远端封面后才尝试已归档正文首图。

内容详情的 `media_segments` 与全局搜索时间点复用同一个解析器。只有显式关联当前内容 audio/video 资产、包含合法起止秒数且未越过已知时长的 `chapter` / `transcript` 切片才进入稳定 contract；发布日期、推断时间和跨内容资产不会进入播放器导航。

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

- 图片代理与媒体访问修复记录：`../../issues/archive/media-proxy-image-access.md`
- 统一资产表、签名访问、解析后写入和旧数据回填已建立；代理 MIME/错误阶段、事件循环阻塞边界、冷请求并发和低频配额已收敛；前端嵌套内容、队列预览及后端 Telegram/QQ 分发 payload 已迁移。前端资产图片会单次刷新过期 manifest，本地 404 会触发服务端核验；签名 blob 的 Range 回归已覆盖。仓库实验数据库/存储的真实 FastAPI 探针已依次得到 Range 206、过期 410、刷新后完整读取 200，并把实际缺失变体从 ready 校正为 missing/repairable。真实平台媒体发送以及浏览器/原生端长音视频播放与后台恢复仍未验收。

## 尚未实现 / 计划扩展

图片可达性和完整富媒体归档都是系统构想中的目标能力；何时实施由用户选择的当前功能切片决定，开始前重新核对真实样本、存储策略和平台能力。
