# Navigation Shell

## 文档状态

active

## 当前代码

- `frontend/lib/layout/app_shell.dart`
- `frontend/lib/core/layout/responsive_layout.dart`

## 当前职责

- 桌面使用 `NavigationRail`，仅展示动态、收藏库、自动化三个主入口。
- 移动端使用 `NavigationBar`，仅展示动态、收藏库、自动化三个主入口。
- 包装 `StatefulNavigationShell` 并在主分支间切换。
- 在内容区右上角提供顶部工具入口：通知中心、设置。

## 不承担职责

- 不执行业务动作。
- 不持有页面业务状态。
- 不决定账号、设置或自动化的功能边界。

## 状态与输入输出

- 输入：`StatefulNavigationShell` 当前分支、屏幕宽度、用户点击的导航目标。
- 输出：桌面 `NavigationRail`、移动 `NavigationBar`、顶部工具入口和当前分支内容。
- 副作用：只执行路由跳转，不直接调用业务 API。

## 响应式和失败态要求

- 桌面：主导航只展示动态、收藏库、自动化，通知中心和设置放在顶部工具区。
- 移动：底部导航只展示动态、收藏库、自动化，通知中心和设置放在顶部工具区。
- 加载：路由守卫跳转期间不得显示错位导航。
- 空状态：无。
- 错误状态：路由异常应落到可理解的错误页或保持当前页，不执行业务动作。

## 当前问题

无当前已确认问题。旧桌面 utility group 与主导航混排问题已通过删除 rail utility actions、改用顶部工具入口关闭，见 `../../issues/archive/frontend-navigation-utility-group-layout.md`。

## 设计约束

主导航只承载 Root Shell 高频业务入口。通知中心、设置、任务详情、账号与平台、Agent/RAG 等均不得作为同级主导航项；需要保留的工具或深链入口应放入顶部工具区、设置 Section Shell 或具体业务下钻。
