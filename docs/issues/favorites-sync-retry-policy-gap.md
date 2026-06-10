# 收藏同步重试入口未统一接入平台 enabled 策略

## 状态

active

## 现象

- 文档要求同步、手动、重试和 Agent 入口都应通过同一自动化策略检查。
- 当前 `POST /favorites-sync/sync` 的单平台手动同步会调用 `AutomationPolicyService().favorites_platform_manual(...)`。
- 但 `POST /favorites-sync/runs/{run_id}/retry`、`POST /favorites-sync/items/retry`、`POST /favorites-sync/items/batch-retry` 在 `backend/app/routers/system.py` 中没有看到同类策略检查。

## 影响范围

- 页面：自动化页收藏同步 tab、动态页 run 入口、任务结果页、Agent 工作台。
- 后端模块：favorites-sync、config-system、events-tasks、agent。
- 数据：收藏同步 run、失败收藏项、导入内容。
- 用户影响：用户禁用某平台收藏同步后，失败项重试或 run retry 仍可能导入内容，前端“禁用”语义无法真正约束后端副作用。

## 复现方式

1. 在设置或账号/自动化页面禁用某个平台的收藏同步。
2. 找到该平台历史失败 run 或失败 item。
3. 调用 `/favorites-sync/runs/{run_id}/retry`、`/favorites-sync/items/retry` 或 `/favorites-sync/items/batch-retry`。
4. 检查后端是否仍创建 retry run 或调用 `ContentService.create_share()`。

## 根因分析

- 收藏同步平台 enabled 策略只在部分入口执行，重试入口复制了同步/导入逻辑但没有统一调用策略服务。
- 单项和批量失败项重试直接在 router 内调用 `ContentService.create_share()`，绕过了 task/service 层的策略边界。
- 现有 `frontend-control-policy-gaps.md` 记录的是泛化控制面缺口，未单独锁定收藏同步重试的具体入口。

## 关联代码

- `backend/app/routers/system.py`
- `backend/app/tasks/favorites_sync.py`
- `backend/app/services/automation_policy.py`
- `backend/app/services/content_service.py`
- `frontend/lib/features/settings/providers/favorites_sync_provider.dart`
- `frontend/lib/features/automation/widgets/favorites_sync_automation_panel.dart`

## 关联文档

- `../backend/modules/favorites-sync.md`
- `../backend/modules/config-system.md`
- `../backend/modules/events-tasks.md`
- `../backend/api.md`
- `../frontend/pages/automation.md`
- `frontend-control-policy-gaps.md`
- `backend-system-router-boundary-pollution.md`

## 修复建议

- 最小修复：在 run retry、item retry、batch retry 三类入口增加同一平台 enabled 策略检查，禁用时返回明确 policy error。
- 如果需要强制重试：新增显式 `force` contract，并要求前端确认，不允许隐式绕过。
- 长期修复：将 retry 编排下沉到 favorites sync service/task，router 不直接执行导入。

## 验证方式

- 自动测试：后端 API 测试覆盖 disabled platform 下三类 retry 返回明确 `409` 或 documented policy error。
- 前端测试：禁用平台时失败项 retry 按钮不展示或禁用，并显示原因。
- 手动验收：禁用平台后，从自动化页、任务结果页和 Agent 尝试重试，均不能绕过策略。
