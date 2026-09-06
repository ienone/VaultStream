# 后端模块：收藏同步

## 文档状态

active

## 代码位置

- Router: `backend/app/routers/system.py`
- Service: `backend/app/services/favorites_sync_service.py`
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

系统配置决定启用平台和同步策略。同步任务调用平台 fetcher 获取收藏项，再按重复策略写入内容库。正常同步、单项重试和批量重试共用 `FavoritesSyncTask.import_items`，最终均通过 `ContentService` 的 canonical URL 去重与 `ContentSource` 流水写入；部分失败仍保留逐项结果。

同步状态、手动策略、预览、trigger、run retry、单项 retry 和批量 retry 由 `FavoritesSyncService` 统一编排；router 不再直接创建协程、检查平台认证或调用内容导入。动作使用命名响应且所有执行路径稳定返回 `run_id`。`202` 只表示任务已受理，单项/批量同步执行的 `200` 则同时返回导入、跳过和失败统计。

## 测试

长期回归与临时验收边界见 [验证策略](../testing.md)。本模块其余行为在变更时针对性验收，不保留逐方法测试清单。

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
- 定时入口检查 scheduler policy；单平台手动、run retry、item retry 和 batch retry 在创建执行性 run 或导入前检查 `favorites_platform_manual`。默认禁用返回统一 `409`；已有 `force`/允许禁用平台手动同步配置只沿原 contract 生效。
- `scope=all` 每次只读取当前启用平台，不从历史 run 恢复已禁用平台。

## 当前问题

- 统一任务结果 contract 解决记录：`../../issues/archive/task-run-result-contract-missing.md`
- System router 职责收敛记录：`../../issues/archive/backend-system-router-boundary-pollution.md`

## 尚未实现 / 计划扩展

收藏同步 run 的摘要、平台结果和失败项处理已迁入统一任务页；自动化页只保留发起、策略、平台状态和最近运行入口。
