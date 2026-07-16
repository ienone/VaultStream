# 任务结果页

## 文档状态

active

## 当前代码

- 页面：`frontend/lib/features/dashboard/task_result_page.dart`
- 路由：`/tasks/:runId`

## 用户任务与当前界面

用户可以查看一次后台运行的任务类型、状态、时间、触发来源、关联对象、错误、metadata 和 result。页面支持加载、失败重试和手动刷新；结构化 payload 当前以可选择的格式化 JSON 展示。

页面本身暂不提供通用业务重试，因为不同任务的权限、参数和副作用不同。业务动作仍应由任务类型 renderer 或对应领域页面提供。

动态页和收藏同步区域仍有各自的运行详情弹层，与本页重复。

## 自适应行为

- 基础字段在窄屏允许标签和值换行，不依赖固定横向表格。
- 大型 payload 保持可滚动、可选择，不撑破页面宽度。
- 后续任务类型 renderer 在宽屏可以增加摘要/原始数据分栏，窄屏保持单列。

## 承担职责

- 后台运行结果的统一深链接落点。
- 提供稳定的状态、错误和诊断信息。

## 不承担职责

- 不复制收藏同步、分发、解析等完整业务界面。
- 不用一个通用按钮猜测所有任务的重试方式。

## API 关联

- 领域：`../../backend/api/agent-system-events.md`
- 主要读取：`GET /api/v1/background-tasks/runs/{run_id}`。

## 当前问题

- 统一 run contract 与 renderer 缺口：`../../issues/task-run-result-contract-missing.md`
