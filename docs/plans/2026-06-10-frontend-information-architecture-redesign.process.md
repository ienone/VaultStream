# 前端信息架构与自适应 UI 重设计执行记录

## 状态

in_progress

## 对应 Plan

- `./2026-06-10-frontend-information-architecture-redesign.plan.md`

## 实际执行记录

- 2026-06-10：根据产品方向讨论创建前端信息架构与自适应 UI 重设计 plan。
- 2026-06-10：本次仅完成规划文档落地，尚未修改前端代码、路由、页面或测试。
- 2026-06-10：将“左侧深色导航 + 右侧灰色背景圆角 surface”从具体样式约束调整为 Section Shell 的层级表达原则；灰底圆角仅作为设置/表单场景的推荐表达之一。
- 2026-06-10：扩写 plan 的“页面设计规划”章节，补充动态信息流、收件箱并入、收藏库筛选/详情/RAG、自动化三大域、通知中心、任务详情和设置分区的详细页面级设计。
- 2026-06-11：执行 Root Shell / 导航收敛切片：`AppShell` 桌面和移动主导航从动态、收藏库、收件箱、自动化四入口收敛为动态、收藏库、自动化三入口；删除桌面 rail utility actions 和移动端辅助 FAB/Menu，顶部工具区保留通知中心和设置入口。
- 2026-06-11：调整路由层级：`StatefulShellRoute` 分支收敛为 3 个；删除 `/dashboard`、`/inbox`、`/discovery`、`/accounts`、`/review` 旧路由，不保留兼容 redirect；`/agent` 保留深链路由但不作为 Root Shell 可见入口。
- 2026-06-11：执行动态页内容流化的止血切片：动态页推荐候选摘要不再提供“查看候选”按钮，不再写 `discoveryFilterProvider` 或跳转旧 `/inbox`；统计项仅作为动态内摘要展示。
- 2026-06-11：执行账号入口降级切片：设置连接 tab 和自动化健康矩阵中的“账号中心”文案改为“账号与平台”，跳转目标改为 `/settings?tab=accounts`。
- 2026-06-11：按 IA 处置 issue：`frontend-navigation-utility-group-layout.md` 判定为 `resolved_by_removal` 并归档；`frontend-discovery-placeholder-actions-leak.md` 判定为 `resolved_by_removal` 并归档；`frontend-account-entry-responsibility-duplication.md` 判定为 `absorbed_by_plan`，记录本轮只完成入口降级，设置 Section Shell 和账号动作收敛仍未完成。
- 2026-06-11：同步更新前端总览、导航、Navigation Shell、动态页、收件箱、自动化、设置、账号页面文档，使当前代码事实与迁移阶段一致。
- 2026-06-11：继续执行设置重构阶段：`SettingsPage` 从 `TabBar` / `TabBarView` 改为 Section Shell。桌面端使用左侧设置分区列表 + 右侧当前分区标题和圆角内容 surface；移动端先显示分区列表，点击后进入全屏详情并通过 AppBar 返回。分区命名改为账号与平台、AI 与发现、推送与通知、外观与系统，并保留旧 query tab 别名映射。
- 2026-06-11：按“旧实现直接删除、不保留兼容层”规则继续收敛：删除旧账号中心页面 `frontend/lib/features/accounts/account_center_page.dart`；删除旧 Discovery 页面、详情、候选卡片、批量 sheet，以及仅被旧 Discovery UI 使用的 actions/filter/items/selection provider 和生成文件；保留仍被动态摘要、设置发现源和自动化健康矩阵使用的 discovery models、stats、sources、settings provider。
- 2026-06-11：删除旧页面现状文档 `docs/frontend/pages/accounts.md`、`docs/frontend/pages/discovery.md`；将 `frontend-account-entry-responsibility-duplication.md`、`frontend-discovery-detail-collection-renderer-coupling.md` 以 `resolved_by_removal` 归档。
- 2026-06-11：删除设置“账号与平台”分区内跳转到自身 `/settings?tab=accounts` 的旧入口 tile，账号分区当前直接展示平台健康只读摘要。
- 2026-06-11：执行自动化命名和结构收敛切片：将 `frontend/lib/features/review/` 迁移为 `frontend/lib/features/automation/`，将 `review_page.dart` / `ReviewPage` 收敛为 `automation_page.dart` / `AutomationPage`，同步更新路由 import、跨模块 import、自动化相关测试命名，并删除仍引用已移除旧账号中心与旧 Discovery UI 的测试文件。
- 2026-06-11：按 IA 处置 issue：`automation-review-doc-source-split.md` 判定为 `resolved_by_removal` 并归档；该时点仍保留自动化一级 4 tab 聚合 UI，自动化三域化继续由 `frontend-automation-page-responsibility-overload.md` 跟踪，后续记录已更新当前事实。
- 2026-06-11：执行自动化三域化第一阶段：`AutomationPage` 移除顶层 `TabBar` / `TabBarView` / `TabController`，默认首屏改为自动化总览，展示待分发、已过滤、已推送、需处理指标，以及收藏同步、分发、解析 / 后处理三张域入口卡。
- 2026-06-11：分发队列和推送历史从自动化顶层 tab 收敛为分发域内的局部 `SegmentedButton`；收藏同步域继续复用 `FavoritesSyncAutomationPanel`，解析 / 后处理域暂时复用 `AutomationHealthMatrixPanel`。
- 2026-06-11：按 IA 处置 issue：`frontend-automation-page-responsibility-overload.md` 从 `active` 改为 `in_progress`，记录三域入口已落地但 Section Shell / Detail Shell 下钻、任务详情统一落点和弹窗治理仍未完成。

## 后续规划与交接约束

### 总体原则

- 继续按 `./2026-06-10-frontend-information-architecture-redesign.plan.md` 推进，但实施时遵循仓库重构规则：旧页面、旧路由、旧测试、旧文档职责若已被新 IA 替代，应删除或归档，不保留 redirect、fallback、拒绝测试或双路径兼容层。
- 当前代码事实优先于早期 process 记录。若后续发现本文档前段执行记录与当前代码不一致，应追加新的执行记录说明变更结果，不要回滚到旧状态。
- 每个成规模代码切片完成后，必须同步更新：相关 `docs/frontend/pages/*.md`、`docs/frontend/navigation.md`、相关组件文档、关联 issue 状态，以及本 process 的实际执行记录、验证结果、产出文件和剩余风险。
- 若删除页面或入口，应同步删除对应现状文档，或将问题文档归档为 `resolved_by_removal`；不要在现状文档中描述已删除 UI。
- 若新增或重建 API 调用，必须先读取后端 router/schema/service、现有 API client、相关测试和 `docs/backend/api.md`，不得猜字段或写多格式兼容分支。

### 不得恢复的旧路径

- 不恢复 `/dashboard`、`/inbox`、`/discovery`、`/accounts`、`/review` 旧路由，也不新增到新路由的 redirect 兼容层。
- 不恢复 `AccountCenterPage`；账号连接、检测、解绑、修复能力需要在设置“账号与平台”分区按新职责重建。
- 不恢复旧 `DiscoveryPage` / `DiscoveryDetailPage` / 候选卡片 / 批量 sheet；候选浏览、收藏、忽略、稍后能力需要作为动态信息流的新能力重建。
- 不恢复旧 Discovery 专属 `actions/filter/items/selection` provider；若动态信息流需要类似状态，应建立新的 feed/domain 状态模型。

### 建议下一步顺序

1. 自动化三域化第二阶段：把分发规则详情、推送历史失败处理、收藏同步 run 详情、解析/后处理失败列表继续拆为 Section Shell / Detail Shell 下钻，不长期堆在域内容首屏。
2. 通知中心真实化：替换当前占位 bottom sheet，接入任务摘要、运行中、需要处理、最近完成，任务详情落点统一到 `/tasks/:runId`。
3. 账号与平台新实现：在设置分区内按新职责重建平台连接、检测、解绑和修复流程；这些动作应进入 provider/controller，不直接堆在 UI widget 中。
4. 动态信息流重建：用新的 feed item / digest item 模型替代当前候选统计摘要；候选浏览、收藏、忽略、稍后在动态内完成，不复用旧 Discovery UI。

### 文档同步检查清单

- 改路由 / 入口：更新 `docs/frontend/navigation.md` 和 `docs/frontend/components/navigation-shell.md`。
- 改页面布局 / 职责：更新对应 `docs/frontend/pages/*.md`；如果页面删除，也删除对应页面现状文档。
- 改共享组件 / shell：更新对应 `docs/frontend/components/*.md`。
- 处理 issue：先判断 `still_valid`、`absorbed_by_plan`、`superseded_by_plan`、`resolved_by_removal` 或 `obsolete`，再更新状态；关闭后移动到 `docs/issues/archive/`。
- 每轮结束：更新本 process 的执行记录、验证命令、未验证项、产出文件和后续风险。

## 偏离计划

- 计划外新增：无。
- 计划内未完成：通知中心仍是占位 bottom sheet，尚未接入真实任务/通知数据；账号连接/检测/解绑主流程已随旧账号中心删除，后续需要按设置“账号与平台”新职责重建；自动化三域化只完成首屏和域入口重组，收藏库增强和任务详情统一落点仍未完成。
- 原因：本次先完成自动化页顶层 IA 重组，降低 4 tab 聚合控制台心智；域内旧组件、弹窗和 run detail 需要后续阶段继续拆分。

## 验证结果

- 命令：`rg -n "NavigationDestination|NavigationRailDestination|/inbox|/discovery|/accounts|/dashboard|/review|账号中心|收件箱|discoveryFilterProvider|resetToFilters" frontend/lib/layout frontend/lib/routing frontend/lib/features/dashboard frontend/lib/features/settings/presentation/tabs/connection_tab.dart frontend/lib/features/automation/widgets/automation_health_matrix_panel.dart`
- 结果：确认可见 `NavigationDestination` / `NavigationRailDestination` 均为 3 个；旧 `/inbox`、`/discovery`、`/accounts`、`/dashboard`、`/review` 不再作为路由或 redirect 存在；动态页不再命中 `discoveryFilterProvider` 或 `resetToFilters`；账号可见入口已改为“账号与平台”。
- 命令：`rg -n "加入规则候选|请求分发|修复失败|规则候选|分发请求|待修复" frontend/lib/features/discovery backend/app/routers/discovery.py`
- 结果：仅命中 `parse_failure` 状态文案“待修复”，未命中用户可点击的未闭环 Discovery 动作入口。
- 命令：`rg -n "TabBar|TabBarView|TabController|账号与平台|_SettingsSection" frontend/lib/features/settings/settings_page.dart frontend/lib/features/settings/presentation/tabs/connection_tab.dart frontend/lib/features/automation/widgets/automation_health_matrix_panel.dart`
- 结果：`SettingsPage` 不再命中 `TabBar`、`TabBarView`、`TabController`；命中 `_SettingsSection` 和“账号与平台”入口，说明设置页已切为 Section Shell 结构。
- 命令：`rg -n "AccountCenterPage|account_center_page|DiscoveryPage|DiscoveryDetailPage|discovery_page|discovery_detail_page|discovery_actions_provider|discovery_filter_provider|discovery_items_provider|discovery_selection_provider" frontend/lib`
- 结果：无命中，确认旧账号中心和旧 Discovery UI / 专属 provider 已删除。
- 命令：`rg -n "features/review|features\\review|ReviewPage|review_page|frontend/lib/features/review|lib/features/review|package:frontend/features/review|\.\./\.\./review|\.\./\.\./\.\./review" frontend`
- 结果：无命中，确认旧 `features/review` 路径、`ReviewPage` 类名和 `review_page` 文件名不再存在于前端代码或测试引用中；归档 issue 和 process 历史记录仍保留旧名称作为原现象说明。
- 命令：`rg -n "AccountCenterPage|account_center_page|DiscoveryPage|DiscoveryDetailPage|discovery_batch_action_sheet|discovery_item_card|discovery_actions_provider" frontend/test frontend/lib`
- 结果：无命中，确认旧账号中心测试、旧 Discovery UI 测试和旧 Discovery actions provider 测试未继续引用已删除界面。
- 命令：`rg -n "TabController|TabBarView|bottom: TabBar|SingleTickerProviderStateMixin|_tabIndex" frontend/lib/features/automation/automation_page.dart`
- 结果：无命中，确认自动化页不再使用顶层 tab 控制器或顶层 tab view。
- 命令：`rg -n "自动化总览|解析 / 后处理|find.byType\(TabBar\)" frontend/test/widget/automation_page_test.dart`
- 结果：命中自动化页 widget 测试的新总览和三域入口断言，并确认测试断言顶层 `TabBar` 不存在。
- 命令：未运行 `flutter analyze` / `flutter test`。
- 结果：未完成自动化验证。
- 未验证项：受当前环境/指令限制，本轮未在沙盒外提权运行 Flutter/Dart 命令；尚未完成桌面、平板、手机竖屏、手机横屏截图验收；通知中心、自动化三域化和账号主流程吸收到设置分区仍未实现。

## 产出文件

- 新增：`docs/plans/2026-06-10-frontend-information-architecture-redesign.plan.md`
- 新增：`docs/plans/2026-06-10-frontend-information-architecture-redesign.process.md`
- 修改：`docs/plans/README.md`
- 修改：`frontend/lib/layout/app_shell.dart`
- 修改：`frontend/lib/routing/app_router.dart`
- 修改：`frontend/lib/features/dashboard/dashboard_page.dart`
- 修改：`frontend/lib/features/settings/settings_page.dart`
- 修改：`frontend/lib/features/settings/presentation/tabs/connection_tab.dart`
- 迁移：`frontend/lib/features/review/` → `frontend/lib/features/automation/`
- 重命名：`frontend/lib/features/automation/review_page.dart` → `frontend/lib/features/automation/automation_page.dart`
- 重命名：`frontend/test/widget/review_page_test.dart` → `frontend/test/widget/automation_page_test.dart`
- 修改：`frontend/lib/features/automation/automation_page.dart`
- 修改：`frontend/test/widget/automation_page_test.dart`
- 删除：`frontend/lib/features/accounts/account_center_page.dart`
- 删除：`frontend/lib/features/discovery/discovery_page.dart`
- 删除：`frontend/lib/features/discovery/discovery_detail_page.dart`
- 删除：`frontend/lib/features/discovery/widgets/discovery_batch_action_sheet.dart`
- 删除：`frontend/lib/features/discovery/widgets/discovery_item_card.dart`
- 删除：`frontend/lib/features/discovery/providers/discovery_actions_provider.dart` 及生成文件
- 删除：`frontend/lib/features/discovery/providers/discovery_filter_provider.dart` 及生成文件
- 删除：`frontend/lib/features/discovery/providers/discovery_items_provider.dart` 及生成文件
- 删除：`frontend/lib/features/discovery/providers/discovery_selection_provider.dart` 及生成文件
- 删除：`frontend/test/widget/account_center_page_test.dart`
- 删除：`frontend/test/widget/discovery_inbox_test.dart`
- 删除：`frontend/test/unit/discovery_actions_provider_test.dart`
- 修改：`docs/frontend/README.md`
- 修改：`docs/frontend/navigation.md`
- 修改：`docs/frontend/components/navigation-shell.md`
- 修改：`docs/frontend/pages/dashboard.md`
- 修改：`docs/frontend/pages/automation.md`
- 修改：`docs/frontend/pages/settings.md`
- 删除：`docs/frontend/pages/accounts.md`
- 删除：`docs/frontend/pages/discovery.md`
- 修改：`docs/issues/README.md`
- 归档：`docs/issues/archive/frontend-account-entry-responsibility-duplication.md`
- 归档：`docs/issues/archive/automation-review-doc-source-split.md`
- 归档：`docs/issues/archive/frontend-discovery-detail-collection-renderer-coupling.md`
- 归档：`docs/issues/archive/frontend-navigation-utility-group-layout.md`
- 归档：`docs/issues/archive/frontend-discovery-placeholder-actions-leak.md`

## 后续问题

- 需要继续实现：通知中心所需后端任务取消、进度和通知分类 contract，以及真实通知列表 UI。
- 需要继续实现：在设置“账号与平台”分区按新职责重建账号连接、检测、解绑和修复流程；不得恢复旧 `AccountCenterPage`。
- 需要继续实现：动态页从候选统计摘要走向真实信息流列表 / 详情预览；当前只是移除旧收件箱跳转和 provider 写入。
- 需要继续实现：自动化三域化第二阶段，拆出收藏同步、分发、解析/后处理的 Section Shell / Detail Shell 下钻边界，并将 run detail 迁移到 `/tasks/:runId` 或通知中心。
