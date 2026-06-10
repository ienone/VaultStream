# Navigation Shell

## 文档状态

active

## 当前代码

- `frontend/lib/layout/app_shell.dart`
- `frontend/lib/core/layout/responsive_layout.dart`

## 当前职责

- 桌面使用 `NavigationRail`。
- 移动端使用 `NavigationBar`。
- 包装 `StatefulNavigationShell` 并在主分支间切换。
- 提供 utility actions：Agent、账号、设置。

## 不承担职责

- 不执行业务动作。
- 不持有页面业务状态。
- 不决定账号、设置或自动化的功能边界。

## 状态与输入输出

- 输入：`StatefulNavigationShell` 当前分支、屏幕宽度、用户点击的导航目标。
- 输出：桌面 `NavigationRail`、移动 `NavigationBar`、utility actions 入口和当前分支内容。
- 副作用：只执行路由跳转，不直接调用业务 API。

## 响应式和失败态要求

- 桌面：主导航和 utility group 必须视觉分层，Agent/账号/设置应贴底或折叠。
- 移动：底部导航只展示核心业务入口，utility actions 通过菜单或独立入口承载。
- 加载：路由守卫跳转期间不得显示错位导航。
- 空状态：无。
- 错误状态：路由异常应落到可理解的错误页或保持当前页，不执行业务动作。

## 当前问题

桌面 `NavigationRail.trailing` 中的 utility actions 没有贴底，导致 Agent、账号、设置紧跟主导航。该问题已记录在 `../../issues/frontend-navigation-utility-group-layout.md`。

## 设计约束

主导航和 utility group 必须视觉分层。utility group 可以贴底，也可以在高度不足时折叠，但不能与主导航混成同级。
