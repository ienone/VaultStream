# 后端模块：Agent

## 文档状态

active

## 代码位置

- Router: `backend/app/routers/agent.py`
- Service: `backend/app/services/agent/service.py`
- Tool registry: `backend/app/services/agent/tool_registry.py`
- Tools: `backend/app/services/agent/tools/*`

## 功能

- 管理 Agent 会话。
- 运行 LLM 对话。
- 调用受控工具。
- 对高风险工具调用生成确认请求。
- SSE 推送运行过程。

## 不承担职责

- 不绕过用户级自动化策略。
- 不直接暴露媒体二进制接口。
- 不替代具体业务页面的主流程。

## 实现逻辑

Agent service 构建上下文消息，注册内置工具，运行模型，记录 tool calls、confirmations、runs 和 messages。部分工具通过内部 API bridge 读取或修改系统状态。

## 测试

- `backend/tests/test_api/test_agent_tools.py`
- `backend/tests/test_adapters/test_content_agent.py`
- `backend/tests/test_adapters/test_content_agent_full.py`
- `backend/tests/test_adapters/test_content_agent_real_llm.py`（integration）

## 与其他模块交互

- contents/search/tags/stats: 可读。
- favorites-sync/rules/push: 可能触发副作用。
- config-system: LLM 配置和权限策略。

## 对应前端

- `../../frontend/pages/agent.md`

## API 接口

详见 `../api.md` 的 Agent 相关端点。

## 配置与策略

- Agent 模型配置来自系统设置。
- 工具权限包括 read/write/side-effect 风险等级；副作用工具必须经过确认和策略检查。

## 当前问题

- Agent API bridge 权限边界：`../../issues/backend-agent-api-bridge-policy-bypass.md`
- 用户控制面与自动化策略缺口：`../../issues/frontend-control-policy-gaps.md`

## 尚未实现 / 计划扩展

Agent 安全编排属于总路线第零阶段 contract/策略基线和第六阶段 Agent 能力建设，见 `../../plans/2026-07-17-vaultstream-development-roadmap.plan.md`。
