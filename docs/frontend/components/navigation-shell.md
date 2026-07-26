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
- 桌面在 NavigationRail 底部提供通知中心、设置入口；移动端在底部导航旁的“更多工具”菜单中提供相同入口。

## 不承担职责

- 不执行业务动作。
- 不持有页面业务状态。
- 不决定账号、设置或自动化的功能边界。

## 状态与输入输出

- 输入：`StatefulNavigationShell` 当前分支、屏幕宽度、用户点击的导航目标。
- 输出：桌面 `NavigationRail`、移动 `NavigationBar`、顶部工具入口和当前分支内容。
- 副作用：只执行路由跳转，不直接调用业务 API。

## 响应式和失败态要求

- 桌面：主导航只展示动态、收藏库、自动化，通知中心和设置放在 Rail 底部工具区，不覆盖页面 App Bar。
- 移动：底部导航只展示动态、收藏库、自动化，通知中心和设置收进相邻的“更多工具”菜单。
- 加载：路由守卫跳转期间不得显示错位导航。
- 空状态：无。
- 错误状态：路由异常应落到可理解的错误页或保持当前页，不执行业务动作。

## 当前问题

无当前已确认问题。覆盖页面 App Bar 的浮动工具层已移除；全局工具与三个主导航目的地保持分组。

## 设计约束

主导航只承载 Root Shell 高频业务入口。通知中心、设置、任务详情、独立账号中心、Agent/RAG 等均不得作为同级主导航项；需要保留的工具或深链入口应放入全局工具区或具体业务下钻。账号对象与连接动作不再作为设置 Section Shell 的长期目标职责。
