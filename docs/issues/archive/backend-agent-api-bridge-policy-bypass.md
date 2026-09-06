# Agent API bridge allowlist 过宽且未接入自动化策略

## 状态

archived

## 处置说明

2026-09-06 已关闭。通用 `api_mutation` 不再使用写操作大前缀，只允许内容字段更新和卡片审核；收藏同步、分发队列、外部发送、Bot 进程与设置写入在参数校验阶段拒绝。直接 tool、Action 和 WebSocket 调用不再接受客户端自报 `confirmed`，高风险操作必须创建并决定持久化 confirmation。专用 `push_batch` 在确认后仍检查分发暂停策略。

本次没有扩大 Agent 工具集，也没有执行真实外部同步、发送或模型调用。真实模型流、其余专用工具策略和前端 controller/SSE 边界继续按独立问题验收。

## 原现象

- `backend/app/services/agent/tools/api_bridge.py` 的 `api_mutation` 通过路径前缀允许 Agent 调用 `/api/v1/bot-config`、`/api/v1/favorites-sync`、`/api/v1/distribution-queue`、`/api/v1/targets`、`/api/v1/discovery` 等高风险业务域。
- 该工具的权限级别是 `dangerous`，会触发 Agent 单次确认，但桥接层没有区分写数据库、创建后台任务、真实外部发送、外部同步、进程控制等不同副作用。
- 当前 allowlist 没有接入 `AutomationPolicyService` 或 domain-specific capability 检查。

## 影响范围

- 后端模块：agent、favorites-sync、distribution、accounts-auth、discovery、config-system。
- 前端页面：Agent 工作台、自动化页、设置中的账号与平台分区。
- 数据：内容状态、分发队列、收藏同步 run、bot 配置、发现源。
- 用户影响：用户关闭某项能力后，Agent 仍可能通过通用 mutation 入口触发同类副作用；单次确认不等同于用户级策略。

## 原复现方式

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

## 已采用修复

- 只读目录继续按明确路径范围生成，但写目录改成 method + path template 的显式集合。
- 通用写能力只保留 `PATCH /contents/{content_id}`、`POST /cards/{card_id}/review` 和 `POST /cards/batch-review`。
- 外部或系统副作用只允许经专用领域工具和对应策略执行；confirmation 只表达逐次授权，不覆盖系统策略。

## 验证方式

- `backend/tests/test_api/test_agent_tools.py` 覆盖收藏重试、外部测试发送、Bot restart、批量分发和设置写入均被 bridge 拒绝，并保留内容更新正向用例。
- 同一测试覆盖客户端 `confirmed=true` 不能绕过 confirmation，以及停止、清空、删除后旧确认被取消。
- `push_batch` 覆盖 `distribution_mode=paused` 时即使批准也返回 `distribution_paused`。
