# 后端模块：系统配置与诊断

## 文档状态

active

## 代码位置

- Router: `backend/app/routers/system.py`
- Config service: `backend/app/services/config_service.py`
- Core config: `backend/app/core/config.py`

## 功能

- 系统设置读写。
- 平台健康、AI 能力、后台诊断。
- Dashboard stats、queue overview、tags。
- 收藏同步配置、媒体归档配置、AI 配置等。

## 不承担职责

- 不直接执行平台同步、推送或解析。
- 不替代具体业务模块的 service。
- 不把 router 聚合逻辑继续扩大为业务实现层。

## 实现逻辑

系统配置来自环境变量和持久化 setting。`ConfigService` 提供类型转换和业务配置读取。`system.py` 聚合多个模块状态供前端显示。

## 测试

- `backend/tests/test_config_service.py`
- `backend/tests/test_core_config.py`
- `backend/tests/test_api/test_system.py`
- `backend/tests/test_api/test_system_settings.py`
- `backend/tests/test_api/test_system_extra.py`

## 与其他模块交互

- 几乎所有自动化模块都会读取系统配置。
- 前端设置页、动态页和自动化页都会调用 system API；账号相关操作归入设置“账号与平台”分区。

## 对应前端

- `../../frontend/pages/settings.md`
- `../../frontend/pages/dashboard.md`
- `../../frontend/pages/automation.md`

## API 接口

- `/health`
- `/init-status`
- `/dashboard/stats`
- `/dashboard/queue`
- `/background-tasks/*`
- `/settings`
- `/platform-health`
- `/ai/capabilities`
- `/ai/connectivity-test`

## 配置与策略

- 系统设置应区分普通参数、用户可见能力状态、后端强制策略。
- 自动化策略应横切任务、手动触发和 Agent 工具。

## 当前问题

- System router 职责污染：`../../issues/backend-system-router-boundary-pollution.md`
- 动作型 API contract 缺口：`../../issues/backend-diagnostic-api-contract-is-inline.md`

## 尚未实现 / 计划扩展

模块拆分和 contract 收敛属于总路线第零阶段，见 `../../plans/2026-07-17-vaultstream-development-roadmap.plan.md`。
