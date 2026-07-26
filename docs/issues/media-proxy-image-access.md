# 图片代理和媒体访问不可达

## 状态

active

## 现象

详情页和卡片中图片可能显示红色失败块。当前媒体链路把外链图片默认改写为后端代理，并在代理路径中执行下载、校验、转码、缓存和鉴权。

## 影响范围

- 收藏卡片封面。
- 内容详情首屏头图。
- 富文本图片和媒体网格。
- 分发缩略图。

## 复现方式

1. 打开包含外链图片的收藏内容详情页。
2. 检查前端是否把图片 URL 改写为 `/api/v1/proxy/image?url=...`。
3. 断开或限制上游图片访问，或使用需要特殊 Referer/Cookie 的图片 URL。
4. 观察详情页是否只显示红色失败块，而没有明确失败原因。
5. 对本地 `local://` 媒体和直接可访问外链分别重复验证。

## 根因分析

前端 `media_utils.mapUrl` 对许多外链强制走 `/proxy/image`，甚至所有其他 `http/https` 外链也会走代理。后端 `/proxy/image` 不只是透明代理，还执行 SSRF 检查、下载、像素校验、WebP 转码和本地缓存。任何步骤失败都会让图片不可见。

真实知乎样本还暴露出两个网络边界问题：代理对单次连接失败过于敏感；Windows 网络栈可能把本机代理的 `198.18.0.0/15` Fake-IP 表示为 IPv4-mapped IPv6，旧逻辑会误判为内网地址。代理传输层现对连接失败执行 2 次受控重试，并等价识别这两种 Fake-IP 表示；其他 SSRF、重定向、体积和像素校验保持不变。

另一个真实运行样本中，同一公网图片域名在常驻后端进程内二次解析为 `127.0.0.1`。SSRF 层必须继续拒绝该结果，不能为了消除裂图而放行回环地址。该场景说明展示层需要持有经过后端判定的多个媒体候选，而不是依赖单个代理 URL。

当前 `cover_url`、`thumbnail_url` 和 `media_urls` 只表达单个字符串；归档元数据虽然保留 `orig_url`、本地存储 key 和缩略图 key，内容展示 contract 却没有把它们组织为候选链。后续应统一为“媒体资源 + 有序来源”模型：本地转码/缩略图优先，远端代理与原始 URL 按安全策略降级，并复用于封面、头像、正文图片及未来的音视频来源选择。

## 关联代码

- `frontend/lib/core/utils/media_utils.dart`
- `frontend/lib/core/network/image_headers.dart`
- `frontend/lib/core/widgets/network_thumbnail.dart`
- `backend/app/routers/media.py`
- `backend/app/core/safe_fetch.py`
- `backend/app/media/processor.py`

## 关联文档

- `../frontend/components/media-rendering.md`
- `../backend/modules/media.md`
- `../frontend/pages/content-detail.md`

## 修复建议

1. 前端不要默认代理所有外链。
2. `/proxy/image` 先改回透明流式代理。
3. WebP 转码和缓存移到后台归档任务。
4. 前端失败态区分安全阻止、代理失败、远端失败、鉴权失败。

## 验证方式

- 使用可直接访问外链、需代理外链、本地 `local://`、无效 URL 四类样本测试。
- 前端 widget/unit 测试覆盖 URL 映射。
- 后端 API 测试覆盖代理成功、SSRF 拒绝、上游超时和 Content-Type 拒绝。
