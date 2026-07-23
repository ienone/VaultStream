# 任务结果展示组件边界

## 文档状态

active

## 当前代码

- `frontend/lib/features/dashboard/task_result_page.dart`
- `frontend/lib/features/automation/widgets/favorites_sync_automation_panel.dart`

## 当前职责

- 动态时间线展示近期 run。
- `/tasks/:runId` 展示通用 run 详情。
- 收藏同步面板自带同步 run 详情弹窗。

## 不承担职责

- 不执行业务重试、推送或同步动作。
- 不重复持有各业务域的完整运行详情状态。
- 不替代收藏同步、分发队列或内容后处理页面。

## 状态与输入输出

- 输入：run id、run summary、task metadata。
- 输出：任务详情展示和跳转。
- 副作用：默认无；业务操作应由专用 renderer 或来源页面提供。

## 响应式和失败态要求

- 桌面：任务详情可独立页面展示。
- 移动：避免复杂详情塞入窄弹窗。
- 加载：显示 run 加载状态。
- 空状态：run 不存在时显示明确提示。
- 错误状态：显示后端错误码和可追踪 run id。

## 当前问题

同一类后台 run 被多个组件重复展示的问题见 `../../issues/task-run-result-contract-missing.md`。

## 尚未实现 / 计划扩展

- 无本组件单独计划；统一 run detail 和 task renderer 的边界以 `../../issues/task-run-result-contract-missing.md` 为准。
