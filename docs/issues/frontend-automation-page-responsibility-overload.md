# 自动化页聚合分发、收藏同步、健康诊断和推送历史导致职责过载

## 状态

active

## 现象

- `/automation` 当前由 `ReviewPage` 实现，包含 4 个 tab：分发队列、收藏同步、健康矩阵、推送历史。
- 同一页面既管理分发规则和队列，又触发收藏同步和失败重试，还展示平台/发现源/推送目标健康诊断，并承载推送历史。
- 页面和子组件继续打开多类复杂对话框：规则编辑、规则回填、同步预览、run 详情、失败项重试、解析测试、推送目标测试等。

## 影响范围

- 页面：`/automation`、`/review`。
- 前端模块：`frontend/lib/features/review/*`。
- 后端模块：distribution、favorites-sync、discovery、accounts-auth、events-tasks。
- 用户影响：自动化页变成多业务“控制台”，用户难以区分分发、同步、诊断和历史；任何一个业务域变更都可能污染整个页面。

## 复现方式

1. 打开 `/automation`。
2. 依次查看分发队列、收藏同步、健康矩阵、推送历史四个 tab。
3. 在页面内触发规则编辑、同步预览、run 详情、解析测试或推送目标测试。
4. 观察多个业务域的读写操作和弹层都集中在同一页面树下。

## 根因分析

- 旧 Review/Distribution 页面在没有重新划分信息架构的情况下持续吸纳收藏同步、平台健康和任务结果能力。
- “自动化”被当成所有后台副作用的容器，而不是按用户任务拆分为分发、同步、诊断、历史和任务结果。
- 子组件直接承担 API 写操作和业务 run 详情，缺少独立页面或统一 task renderer。

## 关联代码

- `frontend/lib/features/review/review_page.dart`
- `frontend/lib/features/review/widgets/favorites_sync_automation_panel.dart`
- `frontend/lib/features/review/widgets/automation_health_matrix_panel.dart`
- `frontend/lib/features/review/widgets/rule_config_panel.dart`
- `frontend/lib/features/review/widgets/queue_content_list.dart`

## 关联文档

- `../frontend/pages/automation.md`
- `automation-review-doc-source-split.md`
- `frontend-account-entry-responsibility-duplication.md`
- `frontend-favorites-sync-placeholder-strategy-leak.md`
- `task-run-result-contract-missing.md`
- `frontend-control-policy-gaps.md`

## 修复建议

- 最小修复：停止向 `/automation` 增加新的业务域；健康矩阵降级为状态摘要和跳转，不承载账号修复或完整诊断工作流。
- 中期修复：将收藏同步 run 详情迁移到 `/tasks/:runId`；收藏同步配置只保留已实现且可验证的参数，placeholder 策略移除。
- 长期修复：按业务任务拆分页面或子路由：分发队列/规则、收藏同步、系统诊断、推送历史、任务结果分别拥有明确 owner 和边界。

## 验证方式

- 自动测试：自动化页 widget 测试确认各 tab 不再出现跨域主流程入口，例如账号连接、run 详情弹窗、placeholder 策略选项。
- 手动验收：用户能从自动化页清楚地区分“分发操作”“同步操作”“只读诊断”“历史查看”。
- 结构检查：`ReviewPage` 不再直接绑定多个业务域 SSE、provider invalidation 和复杂弹层编排。
