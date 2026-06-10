# 自动化页聚合分发、收藏同步、健康诊断和推送历史导致职责过载

## 状态

in_progress

## 现象

- `/automation` 当前由 `AutomationPage` 实现，已从顶层 4 tab 改为自动化总览 + 收藏同步 / 分发 / 解析后处理三域入口。
- 第一阶段仍复用旧内容组件：分发域内含队列与规则、推送历史局部切换；收藏同步域仍承载同步触发和失败重试；解析 / 后处理域暂时复用健康矩阵展示平台/发现源/推送目标健康诊断。
- 页面和子组件继续打开多类复杂对话框：规则编辑、规则回填、同步预览、run 详情、失败项重试、解析测试、推送目标测试等。

## 影响范围

- 页面：`/automation`。
- 前端模块：`frontend/lib/features/automation/*`。
- 后端模块：distribution、favorites-sync、discovery、accounts-auth、events-tasks。
- 用户影响：自动化页变成多业务“控制台”，用户难以区分分发、同步、诊断和历史；任何一个业务域变更都可能污染整个页面。

## 复现方式

1. 打开 `/automation`。
2. 从自动化总览进入收藏同步、分发、解析 / 后处理三个域。
3. 在域内容内触发规则编辑、同步预览、run 详情、解析测试或推送目标测试。
4. 观察顶层 IA 已三域化，但具体业务域仍复用旧组件和弹窗，尚未完成 Section Shell / Detail Shell 下钻拆分。

## 根因分析

- 旧分发审核页面在没有重新划分信息架构的情况下持续吸纳收藏同步、平台健康和任务结果能力。
- “自动化”被当成所有后台副作用的容器，而不是按用户任务拆分为分发、同步、诊断、历史和任务结果。
- 子组件直接承担 API 写操作和业务 run 详情，缺少独立页面或统一 task renderer。

## 已完成

- 将 `/automation` 首屏从 4 个顶层 tab 重组为自动化总览。
- 总览展示待分发、已过滤、已推送、需处理指标，以及收藏同步、分发、解析 / 后处理三张域入口卡。
- 将推送失败、同步失败和平台/处理链路异常聚合为“需要处理”面板，并跳转到对应域。
- 将分发队列和推送历史收敛为分发域内的局部 `SegmentedButton` 切换。
- 保留旧 `/review` 删除状态，未新增 redirect 或 fallback。

## 关联代码

- `frontend/lib/features/automation/automation_page.dart`
- `frontend/lib/features/automation/widgets/favorites_sync_automation_panel.dart`
- `frontend/lib/features/automation/widgets/automation_health_matrix_panel.dart`
- `frontend/lib/features/automation/widgets/rule_config_panel.dart`
- `frontend/lib/features/automation/widgets/queue_content_list.dart`

## 关联文档

- `../frontend/pages/automation.md`
- `archive/automation-review-doc-source-split.md`
- `archive/frontend-account-entry-responsibility-duplication.md`
- `frontend-favorites-sync-placeholder-strategy-leak.md`
- `task-run-result-contract-missing.md`
- `frontend-control-policy-gaps.md`

## 修复建议

- 下一步修复：把收藏同步 run 详情迁移到 `/tasks/:runId`；收藏同步配置只保留已实现且可验证的参数，placeholder 策略移除。
- 下一步修复：继续拆分分发域下钻，规则详情、推送历史、失败项处理不再长期堆在同一个页面树下。
- 下一步修复：解析 / 后处理域需要从健康矩阵继续拆成解析历史、失败内容、媒体归档和语义索引等明确入口。

## 验证方式

- 自动测试：自动化页 widget 测试确认首屏展示自动化总览和三域入口，且不再存在顶层 `TabBar`。
- 手动验收：用户能从自动化总览进入“收藏同步”“分发”“解析 / 后处理”，并通过返回按钮回到总览。
- 结构检查：`AutomationPage` 不再使用顶层 `TabController` / `TabBarView`；后续仍需继续减少跨域 SSE、provider invalidation 和复杂弹层编排。
