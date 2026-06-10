# 媒体渲染与图片访问

## 文档状态

active

## 当前代码

- 前端 URL 映射：`frontend/lib/core/utils/media_utils.dart`
- 图片鉴权头：`frontend/lib/core/network/image_headers.dart`
- 图片组件：`frontend/lib/core/widgets/network_thumbnail.dart`
- 后端媒体接口：`backend/app/routers/media.py`

## 当前职责

- 将 `local://` 转为 `/api/v1/media/{key}`。
- 对外链图片按规则转为 `/proxy/image?url=...`。
- 为同源受保护媒体追加 `X-API-Token`。
- 使用 `CachedNetworkImage` 渲染缩略图和失败态。

## 不承担职责

- 前端不应默认把所有外链都强制代理。
- 图片渲染不应阻塞在后端转码和本地缓存上。
- 失败态不应掩盖具体原因。

## 状态与输入输出

- 输入：原始媒体 URL、API base URL、API token、图片尺寸和 fit 参数。
- 输出：可渲染的本地媒体 URL、代理 URL、同源鉴权头和图片/失败占位。
- 副作用：前端映射本身不应产生后端副作用；访问 `/proxy/image` 目前会触发后端下载、转码和缓存，这是当前问题的一部分。

## 响应式和失败态要求

- 桌面：缩略图、详情头图和媒体网格应保持稳定尺寸，不因加载失败改变页面层级。
- 移动：图片失败态不应挤压正文或遮挡操作按钮。
- 加载：显示低干扰 loading 占位。
- 空状态：空 URL 不请求网络，直接返回空占位或不渲染。
- 错误状态：区分远端不可达、代理失败、鉴权失败和安全策略阻止。

## 当前问题

图片代理和媒体访问不可达问题见 `../../issues/media-proxy-image-access.md`。

## 尚未实现 / 计划扩展

无本组件单独计划；透明代理、后台归档和本地媒体读取的拆分边界以 `../../issues/media-proxy-image-access.md` 为准。
