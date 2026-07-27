# 媒体渲染与图片访问

## 文档状态

active

## 当前代码

- 统一媒体 DTO：`frontend/lib/features/collection/models/media_asset.dart`
- 候选执行器：`frontend/lib/core/media/media_candidate_resolver.dart`
- 前端 URL 映射：`frontend/lib/core/utils/media_utils.dart`
- 图片鉴权头：`frontend/lib/core/network/image_headers.dart`
- 图片组件：`frontend/lib/core/widgets/network_thumbnail.dart`
- 后端媒体接口：`backend/app/routers/media.py`

## 当前职责

- 卡片按后端返回的资产顺序选择代表图片；卡片用途下，后端会把有本地变体的图片排在仅远端的封面之前。
- 图片组件按后端顺序逐一请求候选，去除空 URL 和重复 URL；当前候选加载或解码失败后才切换下一项。
- 详情封面、头像、正文图片、媒体网格和全屏图集已贯通同一候选列表；Markdown 中与 `MediaSource` 精确匹配的原图 URL 会还原为该资产的完整候选顺序。
- 视频和音频播放器按相同的候选状态机初始化，当前来源初始化失败后才尝试下一项。
- 签名本地媒体、后端代理和允许直连的原图候选均不携带全局 API Token。
- 旧 `local://` 映射、默认图片代理和鉴权头仍只服务尚未迁移的旧字段调用方，不得扩散到统一媒体路径。

## 不承担职责

- 前端不应默认把所有外链都强制代理。
- 图片渲染不应阻塞在后端转码和本地缓存上。
- 失败态不应掩盖具体原因。

## 状态与输入输出

- 新输入：后端排好序的 `MediaSource[]`、图片尺寸和 fit 参数。
- 旧输入：原始媒体 URL、API base URL、API token；只在迁移窗口保留。
- 输出：单个活动媒体请求；失败时切换下一候选，全部失败后显示稳定占位。
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

- 签名过期后的 manifest 单次刷新、候选失败分类和资产修复上报尚未接入前端状态机。
- `rich_payload` 内嵌的成员卡片、自动化队列预览和分发调用方仍使用旧媒体字段；这些调用方完成迁移前不删除旧映射函数。
- 音视频 Range、播放恢复和后台播放仍按统一计划后续收敛。
