# Agent API bridge allowlist 过宽且未接入自动化策略

## 状态

active

## 处置说明

本轮暂不变更 AI、Agent 与 RAG 实现；该问题保留为活动 issue，待其他基础治理完成后单独设计和修复。

## 现象

- `backend/app/services/agent/tools/api_bridge.py` 的 `api_mutation` 通过路径前缀允许 Agent 调用 `/api/v1/bot-config`、`/api/v1/favorites-sync`、`/api/v1/distribution-queue`、`/api/v1/targets`、`/api/v1/discovery` 等高风险业务域。
- 该工具的权限级别是 `dangerous`，会触发 Agent 单次确认，但桥接层没有区分写数据库、创建后台任务、真实外部发送、外部同步、进程控制等不同副作用。
- 当前 allowlist 没有接入 `AutomationPolicyService` 或 domain-specific capability 检查。

## 影响范围

- 后端模块：agent、favorites-sync、distribution、accounts-auth、discovery、config-system。
- 前端页面：Agent 工作台、自动化页、设置中的账号与平台分区。
- 数据：内容状态、分发队列、收藏同步 run、bot 配置、发现源。
- 用户影响：用户关闭某项能力后，Agent 仍可能通过通用 mutation 入口触发同类副作用；单次确认不等同于用户级策略。

## 复现方式

1. 打开 `backend/app/services/agent/tools/api_bridge.py`。
2. 查看 `_ALLOWED_PREFIXES` 和 `_is_allowed_path()`。
3. 调用 Agent `api_mutation` 工具并传入允许前缀下的写操作，例如收藏同步或分发队列 endpoint。
4. 观察桥接层只做路径前缀、方法和确认检查，没有执行具体业务策略判断。

## 根因分析

- API bridge 使用路径前缀作为能力边界，粒度过粗。
- Agent 工具权限模型只表达“需要确认”，没有表达“是否允许 Agent 调用该业务动作”。
- 自动化策略和业务 service 没有提供统一 capability 表，导致 bridge 无法判断哪些 endpoint 应被禁止或降级为只读。

## 关联代码

- `backend/app/services/agent/tools/api_bridge.py`
- `backend/app/services/agent/tools/push.py`
- `backend/app/routers/agent.py`
- `backend/app/services/automation_policy.py`
- `backend/tests/test_api/test_agent_tools.py`

## 关联文档

- `../backend/modules/agent.md`
- `../backend/README.md`
- `../backend/api.md`
- `frontend-control-policy-gaps.md`

## 修复建议

- 最小修复：从 `api_mutation` allowlist 移除真实外部发送、服务启停、外部同步和批量重试类 endpoint。
- 中期修复：用 endpoint/action capability 表替换路径前缀；每个 mutation 标注风险等级、是否允许 Agent、需要的 policy check。
- 长期修复：Agent bridge 调用业务 service 暴露的 capability，而不是直接信任 HTTP endpoint 前缀。

## 验证方式

- 自动测试：补充 `backend/tests/test_api/test_agent_tools.py`，验证 Agent 调用 `/favorites-sync/sync`、`/targets/send-test`、`/bot-config/service/telegram/restart` 在未授权或策略关闭时被拒绝。
- 正向测试：保留低风险内容字段更新等明确允许 action 的通过用例。
- 手动验收：Agent 工具列表和确认文案能说明真实风险，不再把所有写操作混为单次确认。
