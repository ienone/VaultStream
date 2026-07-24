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
- 提供 `/proxy/image` 外链图片代理。
- 处理归档图片 WebP 转码、缩略图、视频存储、封面主色提取。
- 对远程抓取执行 SSRF 和 Content-Type 限制。

## 不承担职责

- 不决定内容是否应该被推送。
- 不承担平台登录。
- `/proxy/image` 不应承担后台归档任务的全部职责。

## 实现逻辑

媒体归档任务会从 archive metadata 中提取图片/视频 URL，下载后写入本地 storage，并用 `local://` 或 `/api/v1/media/{key}` 供前端访问。图片代理当前还承担下载、像素校验、转码和缓存职责。

## 测试

- `backend/tests/test_api/test_media.py`
- `backend/tests/test_api/test_media_proxy_security.py`
- `backend/tests/test_media_processor_deep.py`
- `backend/tests/test_media_extractor.py`
- `backend/tests/test_media_color.py`
- `backend/tests/test_core/test_safe_fetch.py`

## 与其他模块交互

- contents: 内容详情和列表需要媒体 URL。
- distribution: 推送服务读取缩略图和媒体。
- config-system: 媒体归档开关、质量、数量限制来自系统配置。

## 对应前端

- `../../frontend/components/media-rendering.md`
- `../../frontend/pages/content-detail.md`
- `../../frontend/pages/collection.md`

## API 接口

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

## 当前问题

- 图片代理与媒体访问不可达：`../../issues/media-proxy-image-access.md`

## 尚未实现 / 计划扩展

图片可达性和完整富媒体归档都是系统构想中的目标能力；何时实施由用户选择的当前功能切片决定，开始前重新核对真实样本、存储策略和平台能力。
