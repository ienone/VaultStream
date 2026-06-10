# 动态页 / Dashboard

## 文档状态

active

## 当前代码

- 页面：`frontend/lib/features/dashboard/dashboard_page.dart`
- 组件：`features/dashboard/widgets/*`
- 相关 provider：`dashboardStatsProvider`、`queueStatsProvider`、`discoveryStatsProvider`

## 当前界面内容

- 页面整体是 `Scaffold` + 毛玻璃 `FrostedAppBar`，AppBar 右侧提供刷新按钮。主体是 `RefreshIndicator` 包裹的 `SingleChildScrollView`，内部用纵向 `Column` 组织多个概览 section；页面进入时有淡入动画。
- 加载失败时显示连接错误页：居中云断开图标、错误文案、“重试连接”和“前往设置”两个按钮。

### 顶部统计与待办摘要

- 顶部统计区是响应式 `GridView.count`，宽屏约 4 列，窄屏 2 列；网格禁用自身滚动并嵌入父级滚动视图。统计卡片包括总内容、存储占用、队列积压、解析失败等，每张 `StatCard` 带图标、数值、说明和点击跳转行为。
- 待处理动态摘要卡聚合解析积压、失败异常、待分发、收件箱等指标。卡片顶部根据当前状态切换异常/待处理/无事项文案，下面用 `Wrap` 排列多个指标按钮，窄屏自动换行。

### 队列、分布与趋势

- 队列状态概览使用环形图/图例卡展示队列各状态占比，并提供进入自动化/队列页面的上下文。
- 平台分布卡使用同一套环形图组件展示各平台收藏分布。
- 环形图卡内部通过 `LayoutBuilder` 响应宽度：空间足够时使用 `Row` 横排图表和图例，空间不足时改为 `Column` 上下排列。
- 增长图表卡展示近期内容增长趋势，作为全局趋势概览，而不是收藏库的完整统计页。

### 收件箱、活动时间线与后台诊断

- 推荐候选 section 展示发现候选统计，作为动态信息流迁移过程中的摘要卡；不再提供“前往收件箱”按钮，也不再点击统计项写入收件箱筛选状态。
- 活动时间线卡展示最近后台任务 run。每条记录包含任务名、状态、时间、摘要和查看按钮；点击可查看 run 详情或打开相关工作区。
- 后台诊断卡展示后台任务诊断摘要、异常/运行状态 chips，以及最近异常 run 列表，帮助用户发现系统级问题。

### 跳转与弹出界面

- 页面支持 `highlightRunId` 深链参数；带该参数进入时会自动定位并打开对应 run 的详情。
- 活动时间线的 run 详情使用底部 `showModalBottomSheet`。抽屉可滚动，展示任务名、Run ID、状态、开始/结束时间、错误信息、metadata JSON、result JSON，底部有“关闭”和“打开相关工作区”按钮。
- “打开相关工作区”不是固定跳到任务页，而是根据任务类型分发：收藏同步进入自动化收藏同步 tab，分发相关进入自动化/历史，发现相关回到动态，内容处理相关进入收藏库，其余进入自动化健康或默认工作区。

## 承担职责

- 展示全局近期状态。
- 汇总后台任务和队列概览。
- 作为跨模块概览页跳转到收藏库或自动化，并在动态内摘要展示候选内容状态。

## 不承担职责

- 不应长期承担收藏库专属统计。
- 不应直接承载收件箱详情管理。
- 不应替代任务结果页。

## 与其他页面交互

- 点击统计卡可跳转收藏库并设置过滤条件。
- 收藏同步任务会跳转到自动化页的收藏同步 tab。
- 普通任务可跳转 `/tasks/:runId`。

## 后端/API 关联

- 读取接口：`GET /api/v1/dashboard/stats`、`GET /api/v1/dashboard/queue`、`GET /api/v1/discovery/stats`、`GET /api/v1/background-tasks/diagnostics`。
- 写入接口：无主流程写入；只通过跳转引导其他页面执行动作。
- 后台任务：活动时间线和后台诊断依赖 task/run 状态。

## 当前问题

- 动态页保留过多统计、跨页面过滤和 run 详情入口的问题见 `../../issues/frontend-dashboard-scope-creep.md`。
- 统一任务结果页 renderer contract 缺口见 `../../issues/task-run-result-contract-missing.md`。

## 尚未实现 / 计划扩展

- 无本页单独计划；动态页与收藏页、任务页的职责收敛边界以 `../../issues/frontend-dashboard-scope-creep.md` 和 `../../issues/task-run-result-contract-missing.md` 为准。
