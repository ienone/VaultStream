# 后端模块：收藏同步

## 文档状态

active

## 代码位置

- Router: `backend/app/routers/system.py`
- Fetchers: `backend/app/adapters/favorites/*`
- Task: `backend/app/tasks/favorites_sync.py`
- Config: `backend/app/services/config_service.py`

## 功能

- 同步平台收藏夹或收藏内容。
- 预览同步结果。
- 记录同步 run 和失败项。
- 支持重试 run、单项重试和批量重试。

## 不承担职责

- 不承担账号登录主流程。
- 不展示完整 UI 状态。
- 不直接决定内容分发。

## 实现逻辑

系统配置决定启用平台和同步策略。同步任务调用平台 fetcher 获取收藏项，再按重复策略写入内容库。失败项进入可重试记录。

## 测试

- `backend/tests/test_tasks/test_favorites_sync_task.py`
- `backend/tests/test_api/test_favorites_sync_preview.py`
- `backend/tests/test_config_service.py`
- `backend/tests/test_automation_policy.py`

## 与其他模块交互

- accounts-auth: 依赖平台 Cookie/浏览器认证。
- contents: 同步结果写入内容库。
- events-tasks: 同步 run 和失败项需要可观测。
- agent: Agent 工具可能触发收藏导入，必须受同一策略控制。

## 对应前端

- `../../frontend/pages/automation.md`
- `../../frontend/pages/tasks.md`

## API 接口

- `GET /api/v1/favorites-sync/status`
- `POST /api/v1/favorites-sync/sync`
- `POST /api/v1/favorites-sync/preview`
- `POST /api/v1/favorites-sync/runs/{run_id}/retry`
- `POST /api/v1/favorites-sync/items/retry`
- `POST /api/v1/favorites-sync/items/batch-retry`

## 配置与策略

- 平台 enabled、同步范围、重复策略、取消收藏策略和手动触发策略来自系统配置。
- 定时、手动、重试和 Agent 入口都应通过同一自动化策略检查。

## 当前问题

收藏同步入口和详情展示被多个页面重复承载；部分重试入口可能绕过平台 enabled 策略，需要统一到自动化策略层。

## 尚未实现 / 计划扩展

收藏同步 run 详情应迁移到统一任务结果页或注册专用 task renderer。
