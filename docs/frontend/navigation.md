# 前端导航与页面层级

## 文档状态

active

## 当前实现

路由定义位于 `frontend/lib/routing/app_router.dart`，外壳位于 `frontend/lib/layout/app_shell.dart`。

Root Shell 主导航分支：

- `/home`: 动态页。
- `/collection`: 收藏库。
- `/collection/:id`: 收藏内容详情。
- `/automation`: 自动化总览。
- `/automation/sync`: 收藏同步。
- `/automation/distribution`: 分发队列与规则。
- `/automation/distribution/history`: 推送历史。
- `/automation/processing`: 解析 / 后处理。

已删除旧路由：

- `/dashboard`: 不再保留到 `/home` 的兼容 redirect。
- `/inbox`、`/discovery`: 不再保留到 `/home` 的兼容 redirect。
- `/review`: 不再保留到 `/automation` 的兼容 redirect。

工具入口：

- `/accounts`、`/accounts/:platform`: 独立账号中心与单平台详情。

- 捕获 surface：由三个主页共用的页头保存按钮打开；它不是独立业务分支，应用内与系统分享共用同一 adaptive surface。
- `/connect`: 初始连接页，路由守卫在未初始化时可能跳转到这里。
- `/onboarding`: 初始化/引导页，路由守卫在首次配置时可能跳转到这里。
- `/settings`: 设置，由主页页头工具菜单进入。
- `/tasks/:runId`: 后台任务结果。
- `/agent`: Agent 工作台，由主页页头工具菜单进入。
- `/search`: 全局搜索，由主页页头工具菜单进入；`q`、`kind`、`content_scope` 保持可刷新查询状态。
- `/player`: 展开当前应用级音视频播放会话、时间点书签和待播队列，并为视频切换仅听声音；由 Root Shell mini player 进入，没有会话时显示明确空状态。
- `/notifications`: 消息盒子，由全局工具组进入；深链接和返回保持真实来源。
- `/events/:id`: 跨模板事件详情，由内容详情中的所属事件或加入事件结果进入。

## 承担职责

- 提供三个主业务入口：动态、收藏库、自动化。
- 提供工具入口：全局搜索、Agent 工作台、消息盒子、账号中心、设置。
- 支持部分深链接，例如自动化域入口、设置 tab、全局搜索、任务详情。
- 主分支通过 `StatefulShellRoute.indexedStack` 保留各自页面状态；普通分支切换不清空收藏库查询或筛选，只有收藏库的显式重置动作负责清空。
- 详情和工具使用的命令式导航会同步浏览器 URL；`/collection/:id` 与 `/events/:id` 在根 Navigator 展示，保留可刷新、可分享的语义地址，返回时恢复发起导航的主分支状态。

## 不承担职责

- 不决定业务策略。
- 不直接执行平台登录、同步、推送或后端写操作。
- 不在导航层承载跨页面状态迁移逻辑，除非是明确的 route 参数。

## 计划扩展

- 无导航文档单独计划；Root Shell、动态候选信息流、通知中心和设置入口迁移以 `../plans/2026-06-10-frontend-information-architecture-redesign.plan.md` 为准。
