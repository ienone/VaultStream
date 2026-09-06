# 任务结果展示组件边界

## 文档状态

active

## 当前代码

- `frontend/lib/features/dashboard/task_result_page.dart`
- `frontend/lib/features/automation/widgets/favorites_sync_automation_panel.dart`

## 当前职责

- 动态时间线展示近期 run。
- `/tasks/:runId` 展示任务业务摘要、结果 section、关联对象、允许入口和折叠诊断信息。
- 收藏同步失败项在统一任务页调用现有单项/批量/run retry contract；自动化面板只保留最近运行列表并跳转任务页。

## 不承担职责

- 不提供猜测参数的通用重试、推送或同步动作。
- 不重复持有各业务域的完整运行详情状态。
- 不替代收藏同步、分发队列或内容后处理页面。

## 状态与输入输出

- 输入：run id、run summary、明确的 `metadata` 与 `result`。
- 输出：任务详情展示、实体/领域跳转，以及专用 renderer 明确定义的业务动作。
- 副作用：通用展示默认无；当前只有收藏同步 renderer 复用已存在且受领域策略约束的 retry API。

## 响应式和失败态要求

- 桌面：任务详情可独立页面展示。
- 移动：避免复杂详情塞入窄弹窗。
- 加载：显示 run 加载状态。
- 空状态：run 不存在时显示明确提示。
- 错误状态：显示后端错误码和可追踪 run id。

## 当前边界

- 原始 `metadata/result` 默认折叠到“技术详情”，不再与业务结果同权展示。
- 后端只为真实 producer 生成展示投影；未知任务保持通用状态，不自动获得重试能力。
- 其他任务若需要 mutation，先固定对应领域 contract，再在专用 renderer 接入。
