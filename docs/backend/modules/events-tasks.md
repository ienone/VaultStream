# 后端模块：事件与后台任务

## 文档状态

active

## 代码位置

- Events: `backend/app/core/events.py`、`backend/app/routers/events.py`
- Task state: `backend/app/services/background_task_state.py`
- Tasks: `backend/app/tasks/*`
- Queue adapter: `backend/app/core/queue_adapter.py`

## 功能

- SSE 事件订阅。
- 后台任务 run 状态记录。
- 任务指标、诊断和失败详情。
- 解析、发现、分发、收藏同步等任务执行。

## 不承担职责

- 不决定具体业务任务是否允许执行。
- 不替代业务 service 的失败处理。
- 不在前端重复定义任务详情格式。

## 实现逻辑

任务执行过程写入状态表或内存/数据库状态，并通过 event bus 发送给前端。前端可通过 `/events/subscribe` 获得实时更新，并通过 background task API 查询 run 详情。

## 测试

- `backend/tests/test_background_task_state.py`
- `backend/tests/test_core_events_deep.py`
- `backend/tests/test_tasks/test_parsing_task.py`
- `backend/tests/test_tasks/test_distribution_task.py`
- `backend/tests/test_tasks/test_favorites_sync_task.py`
- `backend/tests/test_tasks/test_discovery_tasks.py`

## 与其他模块交互

- contents、discovery、distribution、favorites-sync、search-rag 都会写入任务状态。
- frontend task result 页面读取 run 详情。

## 对应前端

- `../../frontend/pages/dashboard.md`
- `../../frontend/pages/tasks.md`
- `../../frontend/components/task-result.md`

## API 接口

- `GET /api/v1/events/subscribe`
- `GET /api/v1/events/health`
- `GET /api/v1/background-tasks/diagnostics`
- `GET /api/v1/background-tasks/runs/{run_id}`
- `GET /api/v1/background-tasks/metrics`

## 配置与策略

- 后台任务执行前应读取对应业务策略。
- run 状态应足够支撑统一任务结果页。

## 当前问题

- 统一任务结果 contract：`../../issues/task-run-result-contract-missing.md`

## 尚未实现 / 计划扩展

Task contract 和专用 renderer 尚未进入专项实施；相关问题见 `../../issues/task-run-result-contract-missing.md`，开始处理前需重新核对当前后端响应和前端任务页。
