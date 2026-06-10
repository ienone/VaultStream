# 前端文档总览

## 文档状态

active

前端代码位于 `frontend/lib/`，以 Flutter + Riverpod + GoRouter 组织。当前主要入口包括动态、收藏库、收件箱、自动化，以及工具入口 Agent、账号中心、设置和任务结果页。

## 页面职责索引

- `pages/dashboard.md`: 动态页 / 首页，当前承担全局统计、活动时间线和跨页面跳转。
- `pages/collection.md`: 收藏库列表、搜索、筛选、批量操作。
- `pages/content-detail.md`: 收藏内容详情、正文阅读、媒体展示、后处理状态。
- `pages/discovery.md`: 收件箱 / 发现候选内容处理。
- `pages/automation.md`: 自动化与分发队列、收藏同步、健康矩阵的当前聚合页。
- `pages/accounts.md`: 平台账号中心。
- `pages/settings.md`: 设置页。
- `pages/agent.md`: Agent 工作台。
- `pages/tasks.md`: 后台任务结果页。

## 组件和交互文档

- `navigation.md`: 主导航、工具入口和深链接。
- `components/navigation-shell.md`: `AppShell` 和导航容器。
- `components/media-rendering.md`: 图片、代理、媒体详情和失败态。
- `components/task-result.md`: 任务结果和 run detail 展示边界。

## 页面文档口径

`pages/*.md` 的 `## 当前界面内容` 必须写当前界面事实，而不是只写页面职责。该章节应覆盖：

- 页面首屏、主体区域、工具栏、列表、卡片、表单、按钮、筛选器和状态提示。
- 当前布局结构，包括 `Row`、`Column`、`Stack`、`Grid`、`Wrap`、`Expanded`、`Flexible`、`Sliver`、固定宽度/高度、滚动容器和主要断点。
- 弹出界面和临时 surface，包括 dialog、bottom sheet、drawer、menu、snackbar、license page 等，以及触发入口和承载内容。
- 加载、空状态、错误、选择模式、批量模式、编辑态、禁用态等用户可见状态。
- 会影响界面理解的动画、转场、拖拽、展开/收起行为。

尚未实现的设想不得写进 `## 当前界面内容`，只能放入 `## 尚未实现 / 计划扩展`。已确认问题应链接到 `../issues/`，不要混在界面事实里。

## 当前重点约束

1. 不允许多个页面同时承担账号中心职责。
2. 不允许把计划中的策略占位项暴露为可配置项。
3. 不允许页面 widget 直接堆叠大量 API 写操作；应收敛到 provider/controller。
4. 复杂工作流优先使用独立页面或明确的 adaptive surface，不继续塞进弹窗。
5. 收藏卡片到详情页的共享 `Hero` 转场当前被列为问题，修复前不应继续扩展。

## 尚未实现 / 计划扩展

前端信息架构仍需重做：动态页的收藏统计应迁移到收藏页，账号中心入口应唯一化，自动化页需要从聚合页拆成更清晰的分发、同步和诊断边界。对应问题见 `../issues/frontend-dashboard-scope-creep.md`、`../issues/frontend-account-entry-responsibility-duplication.md` 和 `../issues/frontend-automation-page-responsibility-overload.md`。
