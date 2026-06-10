# 统一任务结果页缺少跨端 renderer contract

## 状态

active

## 现象

- 前端任务页被定义为后台任务结果统一落点，但当前主要展示通用字段、metadata JSON 和 result JSON。
- 动态页活动时间线、自动化收藏同步面板、内容详情后处理面板等位置仍各自展示 run 摘要、失败项和重试入口。
- 后端 `recent_task_runs` 已记录多类任务，但缺少稳定的 task type 到前端 renderer 的元数据 contract，例如 `display_summary`、`entity_links`、`allowed_actions`、`retry_policy`、`error_code`。

## 影响范围

- 页面：`/tasks/:runId`、动态页、自动化页、内容详情页。
- 后端模块：events-tasks、favorites-sync、distribution、discovery、contents、search-rag。
- 数据：background task run metadata/result、失败项、重试输入、实体链接。
- 用户影响：同一个 run 在不同页面展示不一致；前端继续解析 raw JSON 或复制弹层，难以形成统一任务结果体验。

## 复现方式

1. 触发收藏同步、分发推送、发现源同步、内容后处理等任一后台任务。
2. 分别从动态页、自动化页、内容详情页和 `/tasks/:runId` 查看结果。
3. 观察不同入口展示字段、失败项和重试动作不一致，任务页本身缺少业务化 renderer。

## 根因分析

- 后端 run model 记录了 metadata/result，但没有定义前端可稳定渲染的 task-type schema。
- 前端先以多个业务页弹层解决局部展示，导致统一任务页只成为 raw JSON 落点。
- 现有污染总表提到“run 详情迁移到 `/tasks/:runId`”，但缺少跨端 contract 层面的独立 issue。

## 关联代码

- `backend/app/services/background_task_state.py`
- `backend/app/routers/system.py`
- `frontend/lib/features/dashboard/task_result_page.dart`
- `frontend/lib/features/dashboard/widgets/activity_timeline_card.dart`
- `frontend/lib/features/review/widgets/favorites_sync_automation_panel.dart`
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

## 验证方式

- 自动测试：`GET /api/v1/background-tasks/runs/{run_id}` contract 测试覆盖关键字段。
- 前端测试：对 `favorites_sync`、`distribution_push`、`discovery_sync`、`content_reparse` 等 run 做任务页 renderer widget 测试。
- 手动验收：从动态页、自动化页、内容详情页进入同一 run，展示一致且可理解。
