# 内容详情页

## 文档状态

active

## 当前代码

- 页面：`frontend/lib/features/collection/content_detail_page.dart`
- 详情组件：`features/collection/widgets/detail/*`
- 后处理状态：`post_processing_status_panel.dart`

## 当前界面内容

- 页面根部是 `Stack`：底层放置内容卡片到详情页的 `Hero` 头图/预览区域，上层覆盖透明背景的 `Scaffold`。这种结构用于实现卡片飞入详情页的转场，但也让首屏叠层关系更复杂。
- 页面根据封面或初始颜色动态生成局部 `ColorScheme`，并通过 `Theme` 包裹详情内容，使详情页的按钮、标签和背景色与内容主色保持一致。
- 加载态如果有列表预览数据，会显示 `Hero` 包裹的卡片预览；没有预览时居中显示进度指示器。错误态为居中 `Column`，包含错误图标、错误文本和重试按钮。

### 顶部区域与 AppBar

- 底层 `DetailHeroHeader` 是最大宽度约 720px 的圆角容器，包含 16:9 封面图、平台 badge、作者、标题和最多 4 个标签 pill。封面加载失败时显示 accent 色 fallback 和文章图标。
- 顶部 AppBar 使用毛玻璃背景和 filled tonal 返回按钮。右侧操作区包含生成/更新摘要、重新解析、编辑、删除、阅读原文等按钮；摘要生成中会用小型进度指示器替代图标，删除按钮使用 error 色强调。

### 响应式正文布局

- 页面通过 `LayoutBuilder` 以约 800px 为断点判断横/竖屏。竖屏统一使用 `PortraitLayout`，主体是 `SingleChildScrollView` + `Column`：媒体区、信息容器、富文本正文、payload 渲染依次向下排列。
- 横屏根据内容类型和 layout type 分发到不同布局：
  - 文章布局使用 `Row`，左侧约 13 份 flex 为富文本阅读区，右侧约 7 份 flex 为信息侧栏和目录卡；两侧各自可滚动。
  - 图集布局使用 `Row`，左侧约 6 份 flex 为 `PageView` 图片翻页和横向缩略图列表，右侧约 4 份 flex 为信息卡。
  - 视频布局使用 `Row`，左侧展示封面/媒体列表，右侧用 `Column` 放置信息容器和可滚动简介。
  - 用户资料布局使用 `Row`，左侧为大头像/头像 Hero，右侧为大圆角资料卡，展示作者、平台、摘要、正文和统计。
- 富文本正文复用统一 markdown/rich content 渲染，支持标题锚点、正文段落、媒体块和上下文卡片。

### 信息卡与后处理状态

- 右侧信息卡 `ContentSideInfoCard` 按顺序组合上下文卡、作者头部、标题、统一统计、摘要、后处理状态、标签、可选正文和 payload block。
- 统计区根据平台和内容类型展示点赞、评论、收藏、转发、播放、回答等统一指标；标签区用 `Wrap` 展示普通标签和 AI 标签。
- 后处理状态面板按阶段展示摘要、语义索引、媒体归档、巡逻评分、分发等状态。每行包含状态图标、阶段名、消息、失败摘要、issues/actions 提示和可用操作。
- 后处理面板内可直接触发生成摘要、重建语义索引、重试分发、巡逻评分、重试单个 embedding 分块等动作，结果通过 `SnackBar` 和 provider 刷新反馈。

### 媒体、图集与弹出界面

- 媒体网格按内容类型展示图片、视频封面或图集。图集可打开全屏查看器：透明 `Scaffold`、毛玻璃背景、`PageView` 翻页、`InteractiveViewer` 缩放、双击缩放、垂直拖拽关闭、页码胶囊、桌面左右翻页按钮，以及旋转/下载按钮位。
- 编辑内容打开 `EditContentDialog`，字段包括标题、作者、封面 URL、布局类型、描述、标签和 NSFW 开关。
- 删除内容使用 `AlertDialog` 二次确认，文案强调不可撤销，确认按钮使用 error 色。
- 后处理失败详情使用 `AlertDialog` 展示 failure 键值对，内容可选择复制。
- 页面还存在 `ContentDetailSheet` 轻量底部详情组件：`DraggableScrollableSheet` 可在 0.6 到 0.95 屏高之间拖动，内部展示平台、标题、信息卡、正文和底部原文/分享操作。
- 页面监听内容更新 SSE 事件，收到 `content_updated` 后刷新详情，并结束摘要生成中的 loading 状态。

## 承担职责

- 阅读和检查单条收藏内容。
- 展示解析结果、媒体内容和来源信息。
- 展示后处理状态，例如摘要、语义索引、媒体归档、巡逻评分、分发。

## 不承担职责

- 不承担全局自动化诊断。
- 不承担平台账号修复。
- 不承担长期任务结果归档，run 详情应链接到任务页。

## 与其他页面交互

- 从收藏列表进入。
- 后处理动作可能触发后台任务，并跳转或链接任务结果页。
- 删除或编辑后刷新收藏列表。

## 后端/API 关联

- 读取接口：`GET /api/v1/contents/{content_id}`、`GET /api/v1/contents/{content_id}/processing-status`、`GET /api/v1/media/{key}`。
- 写入接口：`PATCH /api/v1/contents/{content_id}`、`DELETE /api/v1/contents/{content_id}`、`POST /api/v1/contents/{content_id}/re-parse`、`POST /api/v1/contents/{content_id}/generate-summary`、`POST /api/v1/contents/{content_id}/patrol-score`。
- 后台任务：摘要、语义索引、媒体归档、巡逻评分、分发。

## 当前问题

- 详情页首屏重叠问题见 `../../issues/collection-card-detail-transition.md`。
- 图片失败态和媒体访问问题见 `../../issues/media-proxy-image-access.md`。

## 尚未实现 / 计划扩展

无本页单独计划；详情页转场和媒体失败态整改以 `../../issues/collection-card-detail-transition.md` 和 `../../issues/media-proxy-image-access.md` 为准。
