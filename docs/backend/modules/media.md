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
- 提供资源签名授权的 `/proxy/image` 外链图片代理。
- 处理归档图片 WebP 转码、缩略图、视频存储、封面主色提取。
- 对远程抓取执行 SSRF 和 Content-Type 限制。

## 不承担职责

- 不决定内容是否应该被推送。
- 不承担平台登录。
- `/proxy/image` 不应承担后台归档任务的全部职责。

## 实现逻辑

远端目标校验与直连地址解析使用异步 DNS；图片代理和浏览器请求拦截统一等待该结果，不在事件循环执行同步 `socket.getaddrinfo`。目标限制与连接到已核验地址的语义保持一致。

图片归档只保存一个主文件。Pillow 统一编码，按配置质量生成 WebP；已有 WebP 不再次有损编码，转换后未变小时直接保存已验证的源图，不额外保留另一份原图。列表和图集选图条优先使用缩略图：主图不超过 300×300 时复用主文件，其余缩略图也按内容哈希存储。转码、缩略图和主色处理在线程中执行。

每项媒体独立下载并登记结果。临时文件原子写入后发布主文件；缩略图可以从主文件重建。对网络异常、429 和 5xx 重试。

已入库的小红书笔记图片返回 403 时，代理与图片归档共用来源刷新：按资产原始 URL 找到未删除的笔记，重新读取笔记后仅用明确相同的平台图片 ID 匹配新地址，每次下载最多刷新一次。刷新结果按笔记短暂复用，避免同一图集重复解析；仍无法获取的图片保持失败，不按位置替换其他图片。新地址继续经过安全下载、图片校验和既有缓存/归档流程，保留原资产来源身份；归档仍按既有流程替换本地媒体引用，不覆盖正文文本、改变排序或触发推送。

解析先登记媒体资产，正文引用图片 ID。在同一事务内按配置排队归档，后台逐项保存主文件和变体；单项故障按资产 ID 修复。图片归档优先复用已取得的代理缓存。内容列表、详情和 manifest 根据当前请求 origin（或显式 `storage_public_base_url`）生成资源级签名 URL，避免把实际运行在 `8008` 的媒体错误指向配置中的控制面 `8000`。

构建资产时，同一类型和角色同时按原始 URL 与全部变体 storage key 去重。归档记录中的远端原图和内容字段中的本地封面/头像引用，只要共享明确的变体键，就属于同一资产，避免图集重复封面。

完整重解析现在按明确的平台媒体身份、原 URL 或本地变体键复用唯一匹配资产，保留其数据库 ID 与用户书签；不按列表位置猜测。相同种类、相同存储键的变体也保留 ID。解析结果没有重新提供某种本地变体时保留已归档版本，关闭归档不清除既有本地媒体。真实移除的资产仍按既有删除语义清理。Bilibili 使用 bvid + cid 作为 source_identity，CDN 签名变化不改变媒体身份；入库时将时间片的 source_identity 明确绑定到同内容资产 ID，不能跨内容引用。

新解析和发现内容入库的媒体处理读取持久化的归档总开关及图片/视频子开关。`PARSE_SUCCESS` 内容再次进入非 force 的普通解析入口时跳过正文解析，并按归档开关排入独立 `repair_media` 任务。本地失败上报经服务端核验后，存在原始来源时也排入同一持久队列；同一内容和目标资产的待执行/运行中任务合并。修复不重新运行摘要或推送，提交前核对媒体版本和任务所有权，期间发生编辑或删除则放弃旧结果。关闭的媒体类型保持原状态。关闭某一媒体类型只跳过后续下载，不删除已归档资产，也不抢占已经开始的单项下载。

用户文件捕获直接把上传流写入 storage 下的 `.incoming`，计算 SHA-256 后原子移动到内容寻址路径；相同字节复用同一个物理对象。数据库记录保留原文件名、MIME、大小和校验和，调用方只使用 manifest 返回的签名 URL，不接触物理路径。

删除内容时同时读取旧 `local://` 引用和统一 `MediaVariant.storage_key`。数据库关系先删除并提交，再检查剩余内容及媒体变体引用；只有不再被任何内容使用的对象才从 storage 删除，避免内容寻址去重文件被提前清理。

卡片优先使用当前封面资产，无封面时按正文顺序选图，仅剩头像时居中显示小头像。手动修改封面或采纳解析候选时，在同一事务调整封面角色，保留其他资产及变体；旧归档中的 cover 标记不能覆盖当前选择。

内容详情的 `media_segments` 与全局搜索时间点复用同一个解析器。只有显式关联当前内容 audio/video 资产、包含合法起止秒数且未越过已知时长的 `chapter` / `transcript` 切片才进入稳定 contract；发布日期、推断时间和跨内容资产不会进入播放器导航。

切片保留短预览 excerpt 与未经预览截断的 full_text；完整原文与预览通过相同的归属、类型和时间校验，详情逐字稿阅读不能用 280 字预览代替全文。

播放书签存入独立 `media_bookmarks` 表。创建时服务层重新核对内容、媒体资产归属、audio/video 类型和已知时长；同一资产同一毫秒位置不重复创建。笔记可为空，更新只修改用户笔记，不改写解析得到的章节/逐字稿。内容或资产删除时由外键级联清理。

书签删除返回命名 `MediaBookmarkDeleteResponse`，明确删除的书签与内容 ID；前端仍以重新读取书签列表作为显示事实，不从匿名响应猜测对象。

`/proxy/image` 的像素校验、Pillow 解码/转码和缓存目录读取不在事件循环内执行。同 URL 的冷请求按 URL hash 合并，等待者在锁内复查缓存；不同 URL 的冷下载、校验和解码/转码最多同时运行 4 路。配额在进程首次成功写入以及其后每 16 次成功写入检查一次，不再让每个冷请求全量扫描目录。缓存命中按写入格式的固定扩展名映射返回 MIME，避免精简容器缺少 WebP MIME 注册导致重复下载；冷请求用 `X-Cache-Persist` 区分 `stored`、`write-failed` 与 `quota-failed`。缓存是可选加速层，缓存写入失败不应把已经验证并转码完成的图片改写成另一种响应格式。

## 验证

按实际变更执行一次性检查或真实流程验收，边界见[验证策略](../testing.md)。

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

- [图片归档与缓存残留问题](../../issues/2026-09-19-media-localization-integrity.md)：自动补齐与缓存身份已完成本地验收；生产批量处理与部署待确认目标环境。
- [已关闭问题的历史决策](../../issues/archive/README.md)。
- 统一资产表、签名访问、解析后写入和旧数据回填已建立；代理 MIME/错误阶段、事件循环阻塞边界、冷请求并发和低频配额已收敛；前端嵌套内容、队列预览及后端 Telegram/QQ 分发 payload 已迁移。前端资产图片会单次刷新过期 manifest，本地 404 会触发服务端核验。仓库实验数据库/存储的真实 FastAPI 探针已依次得到 Range 206、过期 410、刷新后完整读取 200，并把实际缺失变体从 ready 校正为 missing/repairable。真实平台媒体发送以及浏览器/原生端长音视频播放与后台恢复仍未验收。

## 尚未实现 / 计划扩展

图片可达性和完整富媒体归档都是系统构想中的目标能力；何时实施由用户选择的当前功能切片决定，开始前重新核对真实样本、存储策略和平台能力。

归档落库时删除与当前正文完全相同的文本副本，以及归档中完全相同的多种文本表示；不同的来源文本仍保留。资产重新排序先腾空旧位置，再复用身份和写入新位置，避免封面切换触发唯一键冲突。

历史媒体补齐使用 `scripts/backfill_media_assets.py --db <数据库> --storage-root <媒体目录> --repair-media` 只读统计；加 `--apply` 后按归档开关入队，由现有 worker 执行，入队数量不代表完成数量。无资产的旧内容先使用同一脚本的普通 `--apply` 回填资产。

图片代理复用媒体签名，签名绑定原始目标地址和有效期，不再维护 Origin/Referer 白名单。生成 manifest 和缓存命中不做 DNS 查询；实际下载继续执行地址及重定向 SSRF 校验。代理候选提供 expires_at，前端复用已有一次 manifest 刷新逻辑。

配置 HTTP/SOCKS 代理后，安全传输层允许连接该代理网关，原始目标和每次重定向仍执行地址校验；直连请求使用校验后的 IP。图片下载连接超时为 15 秒、读取空闲超时为 30 秒，含重试和重定向的下载总时限为 120 秒；超时返回 504，并记录异常类型。生产外层 Nginx 的 VaultStream 普通请求读取超时为 150 秒，容器内为 300 秒，均覆盖下载总时限与图片校验、转码所需时间。

## Telegram 原生媒体

账号同步按 Telegram 媒体 ID 和类型复用资产，文字编辑不重复下载；缺少主文件或缩略图时补归档，同一变体键复用原数据库记录。关闭归档或超过限制的附件仍保留媒体身份，后续回查可按新策略补齐。远端确实换图时替换对应资产引用，旧文件由既有无引用回收处理；关闭归档不会删除已归档文件。未新增第二套 HTTP 媒体下载器。
