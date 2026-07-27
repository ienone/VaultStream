# API 领域：Agent、系统与事件

## 文档状态

active

## Agent

- `/api/v1/agent/sessions` 管理会话；消息、运行和上下文摘要归属会话。
- `POST /api/v1/agent/run` 创建运行，增量结果通过 Agent SSE 返回。
- `POST /api/v1/agent/runs/{run_id}/stop` 请求停止当前运行。
- 工具清单和工具调用由 `/agent/tools` 暴露；调用方不能绕开后端权限判断。
- 高风险调用通过 confirmation 资源等待用户决定，确认状态必须与原 tool call 和 run 关联。

Agent API 只提供受控编排能力，不代表 Agent 可以绕过收藏、同步、分发或媒体策略。已知边界问题见 `../../issues/backend-agent-api-bridge-policy-bypass.md`。

## 后台运行与诊断

- `GET /api/v1/background-tasks/runs/{run_id}` 是任务结果的统一读取入口。
- diagnostics 返回最近运行和可恢复失败对象；metrics 返回聚合指标。
- 运行记录至少需要表达任务类型、状态、开始/结束时间、触发来源、错误和任务特定结果。
- 解析、重新解析、摘要、语义索引、发现、同步、分发和连通性测试使用同一 run 观察模型，但结果 payload 仍按任务类型解释。

统一任务结果 contract 的缺口见 `../../issues/task-run-result-contract-missing.md`。

## 健康与能力

- `/health` 与 `/api/v1/health` 返回同一健康结构。
- 健康检查区分数据库、队列、FTS、worker、模型供应商和后台任务状态。
- `GET /api/v1/ai/capabilities` 描述配置与能力，不执行真实模型请求。
- `POST /api/v1/ai/connectivity-test` 执行真实连通性测试并记录 `run_id`。
- `POST /api/v1/platform-health/parse-test` 执行只读真实解析测试，不创建收藏内容、不推进同步 cursor。它与生产解析共用数据库平台凭据和适配器构造逻辑；成功结果包含内容/布局类型、作者字段、封面与媒体、正文长度、发布时间、统计、来源标签，以及结构化扩展和私有归档的键名，便于区分“请求成功”与“字段完整”。响应不返回 Cookie 或完整原始平台 payload。

“已配置”“健康检查通过”“真实业务调用成功”是三个不同层级，界面不得合并为一个布尔状态。

## SSE 事件

- `GET /api/v1/events/subscribe` 提供通用事件流，`/events/health` 提供事件系统健康状态。
- 当前事件用于提示内容变化、分发结果、队列变化和 Bot 同步进度。
- 事件总线采用进程内广播与 SQLite outbox 轮询同步，以支持多实例传播。
- SSE 是刷新提示而不是完整事实源；客户端收到事件后应按需重新读取对应资源。

## 鉴权与错误

- API token 只通过 `X-API-Token` 或 Bearer header 传递，不放入 URL query。
- 业务错误应使用稳定错误码和明确 HTTP 状态，不应只返回自由文本。
- 写操作返回 `run_id` 时必须说明它代表受理、调度还是已经执行。
