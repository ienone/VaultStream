# 收件箱 / 发现页面

## 文档状态

active

## 当前代码

- 页面：`frontend/lib/features/discovery/discovery_page.dart`
- 详情：`frontend/lib/features/discovery/discovery_detail_page.dart`
- provider：`features/discovery/providers/*`

## 当前界面内容

- 页面用于处理尚未进入收藏库的发现候选项。整体支持移动端单列和桌面端主从分栏两种形态，核心信息包括候选列表、筛选/排序、多选批量操作、详情预览和候选处理动作。

### 列表与响应式布局

- 页面通过 `LayoutBuilder` 在约 800px 处切换布局。窄屏使用 `Scaffold` + 毛玻璃 `FrostedAppBar` + `RefreshIndicator` + `ListView.builder` 的单列列表；宽屏不使用普通 AppBar，而是 `Stack` 顶部固定毛玻璃 header，下方为左右分栏 `Row`。
- 桌面端左侧为约 360px 的候选列表栏，中间是 `VerticalDivider`，右侧 `Expanded` 嵌入当前选中候选的详情。顶部 header 左半区包含搜索、刷新、筛选按钮，右半区展示详情相关动作。
- 列表支持下拉刷新和无限加载；滚动接近底部时触发继续拉取。
- 候选卡片 `DiscoveryItemCard` 使用横向 `Row`：左侧 56x56 封面缩略图，中间 `Expanded` 文本列展示标题、类型/状态 chips、来源和时间，右侧是 AI 评分圆形徽章。卡片支持长按进入多选，选中后通过边框/背景高亮。
- 状态 chip 映射发现流程状态，例如待评分、已评分、待处理、已收藏、已忽略、已过期、已合并等。

### 筛选、搜索与选择模式

- 搜索使用 `SearchAnchor`，可输入关键词并展示建议项；提交后刷新候选列表。
- 筛选通过底部可拖拽 `DraggableScrollableSheet` 展示。筛选项包括显示范围、来源、AI 评分下限 `Slider`、排序字段和排序方向；多个选项使用 `Wrap` 排列 chips，窄屏下自动换行。顶部提供重置，底部用主按钮应用筛选。
- 多选模式下 AppBar 替换为选择工具栏，显示已选数量、全选按钮和关闭按钮；右下角 `FloatingActionButton.extended` 显示“操作 (N)”，点击打开批量操作底部抽屉。

### 详情预览与详情页

- 详情页支持两种形态：桌面端嵌入式详情不创建独立 `Scaffold`，移动端或直接路由进入时使用完整详情页和 AppBar。
- 详情内容包含标题、来源、时间、AI 评分、AI 分析理由、AI 标签、正文富文本、媒体/图集，以及复用收藏详情模块的侧边信息卡。
- 详情的元信息使用 `Wrap` 布局展示评分药丸、来源 chip 和相对时间；AI 分析和标签使用圆角 section card，标签以 chips 自动换行。
- 文章型详情在宽屏下使用左右 `Row`：左侧富文本阅读区，右侧侧栏展示元信息、目录、AI 分析、标签等；画廊/视频类详情复用横屏图集布局，左侧媒体，右侧信息。
- 详情页包含 `PopupMenuButton` 或桌面 header 操作菜单，可执行稍后处理、加入规则候选、请求分发、修复失败等动作。

### 批量与弹出界面

- 批量操作底部抽屉包含批量收藏、批量稍后处理、批量加入规则候选、批量请求分发、批量修复失败、批量忽略等 `ListTile` 操作。
- 筛选底部抽屉为可拖拽面板，支持 0.4 到 0.9 屏高范围内展开。
- 详情中的图片可进入全屏画廊查看，复用收藏详情的全屏图集浏览能力。
- 操作结果和错误通过页面内状态或 `SnackBar` 反馈；列表错误态和详情错误态均提供重试入口。

## 承担职责

- 展示尚未正式进入收藏库的候选内容。
- 支持用户审核、收藏、忽略或批量处理发现项。
- 呈现发现源同步后的中间状态。

## 不承担职责

- 不承担收藏库正式内容管理。
- 不承担分发队列操作。
- 不承担平台账号连接配置。

## 与其他页面交互

- 动态页可跳转到收件箱并带过滤状态。
- 候选内容收藏后进入收藏库。
- 发现源配置目前在设置页/自动化相关区域存在交叉。

## 后端/API 关联

- 读取接口：`GET /api/v1/discovery/items`、`GET /api/v1/discovery/items/{item_id}`、`GET /api/v1/discovery/stats`。
- 写入接口：`PATCH /api/v1/discovery/items/{item_id}`、`POST /api/v1/discovery/items/bulk-action`、发现源同步/测试接口。
- 后台任务：发现源同步、发现清理、巡逻评分。

## 尚未实现 / 计划扩展

无本页单独计划；收件箱占位动作问题以 `../../issues/frontend-discovery-placeholder-actions-leak.md` 为准；动态页与收件箱边界以 `../../issues/frontend-dashboard-scope-creep.md` 为准。
