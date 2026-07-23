# 前端导航与页面层级

## 文档状态

active

## 当前实现

路由定义位于 `frontend/lib/routing/app_router.dart`，外壳位于 `frontend/lib/layout/app_shell.dart`。

Root Shell 主导航分支：

- `/home`: 动态页。
- `/collection`: 收藏库。
- `/collection/:id`: 收藏内容详情。
- `/automation`: 自动化页。

已删除旧路由：

- `/dashboard`: 不再保留到 `/home` 的兼容 redirect。
- `/inbox`、`/discovery`: 不再保留到 `/home` 的兼容 redirect。
- `/accounts`: 不再保留到 `/settings?tab=accounts` 的兼容 redirect。
- `/review`: 不再保留到 `/automation` 的兼容 redirect。

工具入口：

- `/connect`: 初始连接页，路由守卫在未初始化时可能跳转到这里。
- `/onboarding`: 初始化/引导页，路由守卫在首次配置时可能跳转到这里。
- `/settings`: 设置，当前由 Root Shell 顶部工具按钮进入。
- `/tasks/:runId`: 后台任务结果。
- `/agent`: Agent 工作台，当前保留深链路由但不作为 Root Shell 可见入口。

## 承担职责

- 提供三个主业务入口：动态、收藏库、自动化。
- 提供工具入口：通知中心、设置。
- 支持部分深链接，例如自动化域入口、设置 tab、任务详情。

## 不承担职责

- 不决定业务策略。
- 不直接执行平台登录、同步、推送或后端写操作。
- 不在导航层承载跨页面状态迁移逻辑，除非是明确的 route 参数。

## 当前问题

- 动态页尚未形成完整的候选信息流，迁移过程见 `../plans/2026-06-10-frontend-information-architecture-redesign.plan.md`。

## 计划扩展

- 无导航文档单独计划；Root Shell、动态候选信息流、通知中心和设置入口迁移以 `../plans/2026-06-10-frontend-information-architecture-redesign.plan.md` 为准。
