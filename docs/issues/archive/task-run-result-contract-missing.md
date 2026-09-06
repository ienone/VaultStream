# 统一任务结果页缺少跨端 renderer contract

## 状态

archived（2026-09-06 已解决）

## 现象

- 前端任务页被定义为后台任务结果统一落点，但当前主要展示通用字段、metadata JSON 和 result JSON。
- 自动化收藏同步面板等业务页仍各自展示 run 摘要、失败项和重试入口；内容详情后处理面板已经把完整结果跳转统一到 `/tasks/:runId`，动态页旧活动时间线已经删除。
- 后端 `recent_task_runs` 已记录多类任务，但缺少稳定的 task type 到前端 renderer 的元数据 contract，例如 `display_summary`、`entity_links`、`allowed_actions`、`retry_policy`、`error_code`。

## 影响范围

- 页面：`/tasks/:runId`、动态页、自动化页、内容详情页。
- 后端模块：events-tasks、favorites-sync、distribution、discovery、contents、search-rag。
- 数据：background task run metadata/result、失败项、重试输入、实体链接。
- 用户影响：同一个 run 在不同页面展示不一致；前端继续解析 raw JSON 或复制弹层，难以形成统一任务结果体验。

## 复现方式

1. 触发收藏同步、分发推送、发现源同步、内容后处理等任一后台任务。
2. 分别从自动化页、内容详情页和 `/tasks/:runId` 查看结果。
3. 观察不同入口展示字段、失败项和重试动作不一致，任务页本身缺少业务化 renderer。

## 根因分析

- 后端已提供持久化 run model 和稳定核心字段，但没有定义前端可业务化渲染的 task-type schema。
- 前端早期以多个业务页弹层解决局部展示；部分入口已经迁移到统一任务页，但业务化 renderer 尚未建立。
- 现有污染总表提到“run 详情迁移到 `/tasks/:runId`”，但缺少跨端 contract 层面的独立 issue。

## 关联代码

- `backend/app/services/background_task_state.py`
- `backend/app/routers/system.py`
- `frontend/lib/features/dashboard/task_result_page.dart`
- `frontend/lib/features/automation/widgets/favorites_sync_automation_panel.dart`
- `frontend/lib/features/collection/widgets/detail/components/post_processing_status_panel.dart`

## 关联文档

- `../backend/modules/events-tasks.md`
- `../backend/api.md`
- `../frontend/pages/tasks.md`
- `../frontend/components/task-result.md`
- `frontend-dashboard-scope-creep.md`
- `frontend-automation-page-responsibility-overload.md`
- `frontend-post-processing-panel-side-effects.md`
- `backend-diagnostic-api-contract-is-inline.md`

## 修复建议

- 最小修复：所有已有“查看日志/查看详情”入口统一跳转 `/tasks/:runId`，停止新增业务页 run 详情弹层。
- 中期修复：定义 task renderer contract，包括 `task_type`、`display_summary`、`entity_links`、`allowed_actions`、`retry_inputs`、`error_code`、`result_sections`。
- 长期修复：为高频任务类型建立专用 renderer，业务页只负责发起动作和跳转任务页。

## 解决记录（2026-09-06）

- M30 已将旧 `SystemSetting` run JSON 迁入 `background_task_runs`；写入改为并发安全 upsert，`run_id` 可直接查表，诊断不再维护固定任务名白名单。
- 通用 API 核心 contract 已固定为 `run_id`、`task`、`status`、时间、`error`、`metadata` 和 `result`；前端任务模型只消费明确的 `metadata`。
- 仓库实验库 15 条旧 run 已迁移，旧 run JSON 键为 0，schema version 为 30。
- `GET /background-tasks/runs/{run_id}` 与 diagnostics 中的 run 现包含读取时生成的 `presentation`：`kind`、业务标题/摘要、可识别错误码、实体链接、安全导航动作和结构化结果 section。
- 收藏同步、内容处理、语义索引、发现、分发、平台/AI 连通性及 Bot 群组同步均有明确 task 映射；未知任务不会根据任意字段猜测操作。
- `/tasks/:runId` 将原始 JSON 折叠为技术详情，并按窗口类别形成单列或业务结果—运行信息双栏。收藏同步旧详情弹窗已删除，最近 run 和 highlight 统一进入该页；原有 run、单项和批量失败重试迁入专用 renderer。
- 账本仍不承担崩溃恢复或任务重放，这是独立的持久执行语义，不属于本 issue。

## 验证方式

- 自动测试：`GET /api/v1/background-tasks/runs/{run_id}` contract 测试覆盖关键字段。
- 前端测试：对 `favorites_sync`、`distribution_push`、`discovery_sync`、`content_reparse` 等 run 做任务页 renderer widget 测试。
- 手动验收：从动态页、自动化页、内容详情页进入同一 run，展示一致且可理解。
