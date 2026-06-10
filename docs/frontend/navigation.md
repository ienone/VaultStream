# 前端导航与页面层级

## 文档状态

active

## 当前实现

路由定义位于 `frontend/lib/routing/app_router.dart`，外壳位于 `frontend/lib/layout/app_shell.dart`。

主导航分支：

- `/home`、`/dashboard`: 动态页。
- `/collection`: 收藏库。
- `/collection/:id`: 收藏内容详情。
- `/inbox`、`/discovery`: 收件箱。
- `/automation`、`/review`: 自动化页。

工具入口：

- `/connect`: 初始连接页，路由守卫在未初始化时可能跳转到这里。
- `/onboarding`: 初始化/引导页，路由守卫在首次配置时可能跳转到这里。
- `/agent`: Agent 工作台。
- `/accounts`: 账号中心。
- `/settings`: 设置。
- `/tasks/:runId`: 后台任务结果。

## 承担职责

- 提供四个主业务入口：动态、收藏库、收件箱、自动化。
- 提供工具入口：Agent、账号、设置。
- 支持部分深链接，例如自动化 tab、设置 tab、任务详情。

## 不承担职责

- 不决定业务策略。
- 不直接执行平台登录、同步、推送或后端写操作。
- 不在导航层承载跨页面状态迁移逻辑，除非是明确的 route 参数。

## 当前问题

- 导航 utility 分组问题见 `../issues/frontend-navigation-utility-group-layout.md`。
- `/automation` 与 `ReviewPage` 命名不一致问题见 `../issues/automation-review-doc-source-split.md`。

## 计划扩展

- 无导航文档单独计划；规范 utility 分组以 `../issues/frontend-navigation-utility-group-layout.md` 为准，旧 `/review` 别名处理以 `../issues/automation-review-doc-source-split.md` 为准。
