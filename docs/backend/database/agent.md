# 数据库领域：Agent

## 文档状态

active

## ORM 来源

- `backend/app/models/agent.py`

## 会话与消息

- `agent_sessions` 保存会话标题、状态、上下文预算和软删除时间。
- `agent_messages` 保存会话中的 user、assistant、tool 等消息，可通过 `run_id` 关联一次运行，并用 payload 承载结构化事件。工具完成或失败时同时保存 `tool`、`tool_call_id`、`ok` 以及 `result` / `error`，使刷新后的会话能恢复引用和诊断；`agent_tool_calls` 仍是调用状态与完整审计记录。

会话是长期容器，run 是一次执行。清空或删除会话时应明确消息、运行、工具调用和摘要的级联行为。

## 运行

`agent_runs` 保存输入、输出、状态、错误和 usage。`usage` 是结构化模型消耗记录，不应只保存一个总 token 数；供应商、模型、缓存和不同 token 类型的日志设计属于后续独立计划。

## 工具与确认

- `agent_tool_calls` 保存工具名、权限级别、参数、结果、错误和状态。
- `agent_confirmations` 把高风险决定关联到 session、run 和 tool call，并保存用户决定与时间。

确认记录不是普通聊天消息的替代品。任何批准都必须能回到原调用参数，且不得被后续 run 复用。等待状态可以转为 `approved`、`rejected`、`failed` 或 `cancelled`；停止 run、清空或删除 session 会取消仍在等待的记录，防止失去上下文后继续执行。

## 上下文摘要

`agent_context_summaries` 保存压缩摘要、覆盖消息数和 token 估算，可选关联产生它的 run。摘要用于降低上下文成本，但不能删除仍需审计的原始消息和工具记录。

## 关系与索引

- session 删除对 message、run、tool call 和 confirmation 使用级联关系。
- run 删除会级联工具调用与确认；context summary 的 run 关联允许置空。
- `agent_context_summaries.run_id` 的索引有效性仍需结合实际查询计划验证。

## 安全边界

- 工具参数和结果可能包含敏感信息，日志与导出必须经过脱敏。
- 权限级别和确认状态由后端策略解释，不能只依赖前端隐藏按钮。
- usage 与错误记录用于诊断和成本分析，不应包含 API key。
