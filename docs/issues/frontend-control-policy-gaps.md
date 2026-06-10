# 前端控制面与后端自动化策略缺口

## 状态

active

## 现象

部分前端开关或状态展示不能真正约束后端自动行为。用户看到“关闭/禁用”时，后台任务、手动触发或 Agent 工具仍可能产生副作用。

## 影响范围

- AI 自动化策略没有统一横切层。
- 自动语义索引缺少总开关。
- 发现源 enabled 主要约束定时同步，不一定约束手动同步。
- 收藏同步平台 enabled 可能不约束单平台手动同步、失败项重试或 Agent 工具。
- 分发自动审批、规则刷新和队列 worker 缺少全局暂停。
- Cookie 保活任务控制面不足。
- Agent 工具权限只有单次确认，不等于用户级策略。
- 媒体归档设置控制面不完整。
- 解析 worker 和队列缺少用户级暂停/成本控制。

## 复现方式

1. 在设置或账号/自动化页面关闭某一类用户可见能力，例如发现源、收藏同步平台或分发相关策略。
2. 通过对应的手动按钮、后台任务入口或 Agent 工具触发同类动作。
3. 检查后端是否仍创建任务、执行同步、执行推送或写入状态。
4. 若前端显示禁用但后端仍执行，即复现控制面与策略缺口。

## 根因分析

配置字段、前端展示和后端副作用入口没有统一策略服务。不同 router、task、Agent tool 直接调用具体服务，导致控制语义分散。

## 关联代码

- `backend/app/routers/system.py`
- `backend/app/services/config_service.py`
- `backend/app/tasks/*`
- `backend/app/services/agent/tools/*`
- `backend/app/services/distribution/*`
- `backend/app/services/embedding_service.py`
- `backend/app/media/processor.py`

## 关联文档

- `../backend/modules/config-system.md`
- `../backend/modules/events-tasks.md`
- `../backend/modules/favorites-sync.md`
- `../backend/modules/agent.md`
- `../frontend/pages/settings.md`
- `../frontend/pages/automation.md`

## 修复建议

- 建立统一 `AutomationPolicyService`，所有后台任务、手动触发和 Agent 工具都通过它判断。
- 将策略结果暴露为用户可理解的 capability 状态。
- 为每类副作用写测试：禁用后定时、手动、重试、Agent 入口都不能绕过。

## 验证方式

- 后端单元测试覆盖每类策略入口。
- API 测试验证禁用策略返回明确错误。
- 前端 widget 测试验证禁用状态不展示可执行动作。
