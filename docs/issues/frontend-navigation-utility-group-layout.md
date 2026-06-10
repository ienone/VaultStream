# 桌面导航 utility group 未与主导航分层

## 状态

active

## 现象

- 桌面端 `NavigationRail` 的 Agent、账号、设置入口位于 `trailing`，但只使用 `Padding(top: 24)`，没有贴底或折叠。
- 这些 utility actions 紧跟动态、收藏库、收件箱、自动化等主业务入口，视觉上像同一级导航。
- 文档要求主导航和 utility group 必须视觉分层，utility group 可以贴底或在高度不足时折叠。

## 影响范围

- 页面：全局桌面布局。
- 组件：`AppShell` / `NavigationRail`。
- 用户影响：主业务入口和工具入口层级混淆；设置/账号/Agent 看起来像核心业务分支。

## 复现方式

1. 在桌面宽度打开前端。
2. 查看左侧 `NavigationRail`。
3. 确认 Agent、账号、设置是否紧贴主导航项，而不是位于底部或折叠 utility 区域。

## 根因分析

- `NavigationRail.trailing` 被当作普通追加区域使用，但没有通过可伸缩布局把 utility group 推到底部。
- 主导航 destinations 和工具入口都放在同一个视觉节奏里，没有分组标题、分隔线或底部定位。
- 移动端使用 utility menu，但桌面端缺少等价的分层规则。

## 关联代码

- `frontend/lib/layout/app_shell.dart`
- `frontend/lib/core/layout/responsive_layout.dart`

## 关联文档

- `../frontend/navigation.md`
- `../frontend/components/navigation-shell.md`
- `automation-review-doc-source-split.md`

## 修复建议

- 最小修复：桌面端将 utility group 贴到底部，必要时在 `NavigationRail` 外层自定义 rail column，以 `Spacer` 分隔主导航和 utility actions。
- 高度不足时，utility group 折叠为单个“更多/工具”按钮，打开与移动端一致的 utility menu。
- 保留主导航只包含四个核心业务入口：动态、收藏库、收件箱、自动化。

## 验证方式

- 手动验收：桌面宽屏、窄桌面和低高度窗口下，Agent/账号/设置都不与主导航混成同组。
- Widget 测试：构建桌面 shell，断言 utility group 位于主导航后独立区域或折叠菜单。
- 截图：保留桌面 rail 高/低窗口两种截图。
