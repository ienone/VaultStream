# 收藏库页面

## 文档状态

active

## 当前代码

- 页面：`frontend/lib/features/collection/collection_page.dart`
- 列表组件：`features/collection/widgets/list/*`
- provider：`features/collection/providers/collection_provider.dart`、`collection_filter_provider.dart`

## 当前界面内容

- 页面整体是 `Scaffold`，内容延伸到 AppBar 背后，常规 AppBar 使用毛玻璃效果覆盖在瀑布流上方。主体外层监听滚动通知，用于根据滚动方向展开/收起新增内容 FAB。
- 列表主体是 `RefreshIndicator` + `CustomScrollView`。内容网格使用 `SliverMasonryGrid.count`，列数由响应式工具根据屏幕宽度计算；滚动到底部时自动 `fetchMore()` 做无限加载。
- 空列表时用 `SliverFillRemaining` 居中显示空态图标和提示；初始加载使用 Masonry 风格骨架屏，渲染多个高度不同的呼吸动画卡片；错误态使用居中错误图标、错误文本和重试按钮。

### 顶部搜索、筛选与 AppBar

- 常规 AppBar 标题为收藏库，右侧依次提供语义/关键词搜索切换、清除当前搜索、刷新、筛选和新增内容等入口。
- 搜索使用 `SearchAnchor` 和 `SearchController`，支持输入关键词、提交搜索、点击历史建议。语义搜索打开时，搜索按钮图标和 tooltip 会切换，筛选对话框中也会出现语义 scope/topK 等参数。
- 筛选入口通过 `OpenContainer` fade 转场打开筛选对话框；当存在活跃筛选时，筛选图标使用主题色强调。
- 选择模式下 AppBar 被普通 `AppBar` 替换：左侧关闭按钮，中间标题显示“已选择 N 项”，右侧提供全选按钮。

### 卡片与瀑布流内容

- 收藏卡片支持 hover 缩放动画，点击进入详情页时使用 `Hero` 转场；转场使用自定义 flight shuttle，以保持列表卡片和详情头图之间的视觉连续。
- 卡片预览根据内容类型展示封面、平台、作者、标题、摘要、统计、标签、NSFW 标记和解析/归档状态。图片比例会根据封面方向自适应，避免瀑布流卡片高度完全一致。
- 卡片支持普通点击进入详情、长按或选择模式下切换选中状态。选中后显示高亮边框/遮罩，用于批量操作。

### 筛选对话框

- 筛选对话框是圆角 `Dialog`，宽度和高度受限，内部可滚动。内容包含平台 chips、状态 chips、标签搜索与自动补全、已选标签 `InputChip`、作者输入、日期范围、搜索模式、语义搜索范围和 topK `Slider`。
- 日期范围既支持今天、近 7 天、近 30 天等预设，也支持打开自定义 `DateRangePicker`；日期选择器使用定制主题，并带 scale/fade 入场动画。
- 对话框底部提供清空、取消和应用筛选操作。

### 新增、批量与弹出界面

- 常规 FAB 是 `FloatingActionButton.extended`，随滚动方向通过 `AnimatedSize` 展开/收起文字，并带轻量 shimmer 动画。点击后打开新增内容底部抽屉。
- 新增内容抽屉是可滚动 `showModalBottomSheet`：顶部有拖动条，包含 URL 输入、快捷标签 `FilterChip`、自定义标签输入、NSFW 开关、错误提示容器，以及取消/提交按钮行。
- 选择模式下 FAB 切换为“操作 (N)”，点击打开批量操作底部抽屉。批量抽屉提供修改标签、标记 NSFW、标记安全、重新解析、删除等操作。
- 批量删除和批量标签编辑会继续打开二级 `AlertDialog` 确认或输入，避免误操作。

## 承担职责

- 浏览、搜索、筛选和管理已收藏内容。
- 作为收藏内容详情页的入口。
- 承接收藏域内的批量操作。

## 不承担职责

- 不承担平台账号登录/解绑。
- 不承担分发规则配置。
- 不承担发现候选内容审核。
- 当前不应继续扩展卡片到详情页的共享 `Hero` 转场。

## 与其他页面交互

- 从动态页统计卡可跳转并设置过滤条件。
- 打开内容进入 `/collection/:id`。
- 分享提交成功后会刷新收藏列表。

## 后端/API 关联

- 读取接口：`GET /api/v1/contents`、`GET /api/v1/cards`、`GET /api/v1/search/semantic`。
- 写入接口：`POST /api/v1/shares`、内容批量审核/编辑相关接口。
- 后台任务：内容解析、语义索引和媒体归档会改变列表展示状态。

## 当前问题

- 收藏统计迁移和收藏域边界问题见 `../../issues/frontend-dashboard-scope-creep.md`。
- 卡片到详情页转场重叠问题见 `../../issues/collection-card-detail-transition.md`。

## 尚未实现 / 计划扩展

无本页单独计划；收藏页与动态页的统计边界以 `../../issues/frontend-dashboard-scope-creep.md` 为准。
