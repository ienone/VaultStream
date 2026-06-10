# Discovery 详情复用收藏详情渲染导致职责耦合

## 状态

archived

## IA 处置结论

- 处置类型：`resolved_by_removal`。
- 处置说明：旧 `/inbox`、`/discovery` 兼容路由已删除，旧 `DiscoveryPage`、`DiscoveryDetailPage`、候选卡片、批量操作 sheet 以及旧 discovery items/filter/action/selection provider 均已删除。原 Discovery 详情复用收藏详情渲染的耦合点已不存在；后续候选信息流应在动态页按新 view model 和 renderer 重建，而不是复用旧 Discovery 详情。
- 归档时间：2026-06-11。

## 现象

- `frontend/lib/features/discovery/discovery_detail_page.dart` 直接导入收藏详情组件，例如 `ContentSideInfoCard`、`RichContent`、`GalleryLandscapeLayout`。
- Discovery 详情把 `DiscoveryItem` 转成 `ContentDetail` 后渲染，导致候选内容详情复用正式收藏详情的信息卡、富文本和图集布局。
- 页面还直接读取 `apiClientProvider` 的 baseUrl/token 并传入媒体组件，使候选内容详情同时耦合媒体访问细节。

## 影响范围

- 页面：Discovery 详情页、收件箱嵌入详情。
- 后端模块：discovery、contents、media。
- 数据：候选内容、正式收藏内容、媒体 URL。
- 用户影响：Discovery 详情会隐式继承收藏详情的正式内容语义和后续改动，候选审核流程与收藏内容管理边界混淆。

## 复现方式

1. 打开 `/inbox` 或 `/discovery`。
2. 选择一条候选内容进入详情。
3. 检查页面渲染代码，确认 `DiscoveryItem.toContentDetail()` 后交给收藏详情组件。
4. 修改收藏详情侧栏或富文本组件时，Discovery 详情会被动改变。

## 根因分析

- Discovery 详情没有自己的 preview renderer 或 adapter view model，而是把候选内容伪装成正式收藏详情。
- 收藏详情组件混合了正式内容元信息、媒体展示和后处理语义，不适合作为 Discovery 页面直接复用的高层组件。
- 媒体 baseUrl/token/header 构造没有下沉到共享 media boundary，导致页面层直接处理传输细节。

## 关联代码

- `frontend/lib/features/discovery/discovery_detail_page.dart`
- `frontend/lib/features/discovery/models/discovery_models.dart`
- `frontend/lib/features/collection/widgets/detail/components/rich_content.dart`
- `frontend/lib/features/collection/widgets/detail/components/content_side_info_card.dart`
- `frontend/lib/features/collection/widgets/detail/layout/gallery_landscape_layout.dart`

## 关联文档

- `../frontend/pages/discovery.md`
- `../frontend/pages/content-detail.md`
- `../frontend/components/media-rendering.md`
- `../backend/modules/discovery.md`
- `../backend/modules/media.md`

## 修复建议

- 最小修复：为 Discovery 增加轻量只读 preview view model，只复用纯展示、无收藏详情语义的低层组件。
- 中期修复：把媒体访问参数构造收敛到共享 media helper/provider，页面不直接传 baseUrl/token。
- 长期修复：明确哪些组件是跨候选/收藏通用渲染层，哪些只属于正式收藏详情，并在组件文档中记录边界。

## 验证方式

- 自动测试：Discovery detail widget 测试覆盖文章、图集、视频三类候选内容。
- 手动验收：桌面嵌入详情和移动全页详情下，确认不出现正式收藏管理语义或后处理入口。
- 截图/日志：保留 Discovery 详情在不同内容类型下的截图。

本次关闭验证：`rg -n "DiscoveryPage|DiscoveryDetailPage|discovery_detail_page|discovery_page" frontend/lib` 不再命中旧页面实现。
