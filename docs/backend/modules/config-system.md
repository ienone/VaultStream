# 后端模块：系统配置与诊断

## 文档状态

active

## 代码位置

- Router: `backend/app/routers/system.py`
- Config service: `backend/app/services/config_service.py`
- AI diagnostics service: `backend/app/services/ai_diagnostics.py`
- Platform health service: `backend/app/services/platform_health_service.py`
- System diagnostics service: `backend/app/services/system_diagnostics_service.py`
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

系统配置来自环境变量和持久化 setting。`ConfigService` 提供类型转换和业务配置读取。AI capability、模型连通性、模型发现和平台解析由 `AIDiagnosticsService` 聚合；平台认证与后台任务诊断分别由专用 service 承担，system router 只负责 contract、依赖注入和 HTTP 错误映射。

布尔开关统一通过 `coerce_bool` 读取，识别布尔值、数字和 `true/false`、`1/0`、`yes/no`、`on/off` 字符串；空值或未知值采用调用方默认值。诊断与自动化策略不再维护各自的转换规则。AI 能力的各状态共用响应组装，保留状态、原因、修复动作和实际连通性结果。

## 测试

长期回归与临时验收边界见 [验证策略](../testing.md)。本模块其余行为在变更时针对性验收，不保留逐方法测试清单。

## 与其他模块交互

- 几乎所有自动化模块都会读取系统配置。
- 前端设置页、动态页和自动化页都会调用 system API；账号相关操作归入独立账号中心。

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

- System router 职责收敛记录：`../../issues/archive/backend-system-router-boundary-pollution.md`
- 当前写动作的成功响应已全部进入命名 JSON response 或显式 bodyless 204 门禁，修复记录见 `../../issues/archive/backend-diagnostic-api-contract-is-inline.md`。

## 尚未实现 / 计划扩展

System router 的跨域副作用、后台诊断账本和 AI capability 聚合均已下沉。dashboard、tags 与 settings 继续作为 system/config 自身的短查询 contract；除非出现新的 owner、策略或测试收益，不再仅为缩短文件拆分同一 URL router。
