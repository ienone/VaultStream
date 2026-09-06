# API 领域：Agent、系统与事件

## 文档状态

active

## Agent

- `/api/v1/agent/sessions` 管理会话；消息、运行和上下文摘要归属会话。
- `POST /api/v1/agent/run` 创建运行，增量结果通过 Agent SSE 返回。
- `POST /api/v1/agent/runs/{run_id}/stop` 请求停止当前运行。
- 工具清单和工具调用由 `/agent/tools` 暴露；调用方不能绕开后端权限判断。
- `search_content` 返回 `items`、`events`、`timepoints` 三组证据；内容定位到收藏详情，事件定位到事件详情，时间点携带明确 `content_id`、`media_asset_id`、`start_seconds` 和内部 `route`。平台与起止时间只过滤内容派生证据，不改变事件域结果。
- 已执行工具的成功或失败 payload 以 `tool` 消息持久化，因此 `GET /agent/sessions/{session_id}/messages` 可恢复结构化工具过程和引用，不把 SSE 当作唯一事实来源。
- 高风险调用通过 confirmation 资源等待用户决定，确认状态必须与原 tool call 和 run 关联；客户端提交 `confirmed` 不能跳过该资源。
- `GET /api/v1/agent/sessions/{session_id}/confirmations` 按会话恢复待确认项，供刷新、切换会话和消息盒子深链继续处理。
- 停止 run、清空会话或删除会话会把所属待确认项置为 `cancelled`；已失去等待上下文的确认不能再次执行工具。
- 清空与删除会话在响应前完成，统一返回包含目标 session ID 的命名 action response，不创建后台 run。
- Telegram Bot `/ai` 调用同一 `POST /agent/run` contract；`waiting_confirmation` 响应显示批准/拒绝按钮，回调核验请求会话归属后调用正式 decision API，不复制工具执行逻辑。
- `capture_content` 是专用写工具：参数必须且只能包含一个非空 `url` 或 `text`，可携带备注、标签、NSFW 和明确模板，文字可有标题；它在确认后复用正式 `ContentService`，而不是借通用 mutation 猜测捕获 API。
- `organize_knowledge_event` 是专用写工具：`create` 必须提供内容 ID 与标题，`add_member` 必须提供内容 ID 与事件 ID；两种动作都可显式设置成员角色、证据状态和关系说明。工具在 confirmation 批准后复用 `KnowledgeEventService`，成员来源记为 `agent`，结果返回可恢复的内容/事件引用。
- 通用 `api_mutation` 只允许内容字段更新和卡片审核；外部同步、发送、Bot 进程、设置和队列写操作必须走领域工具或确定性页面，不能借路径前缀进入。

Agent API 只提供受控编排能力，不代表 Agent 可以绕过收藏、同步、分发或媒体策略。`push_batch` 在确认后仍检查分发暂停策略；通用桥接边界的修复记录见 `../../issues/archive/backend-agent-api-bridge-policy-bypass.md`。

## 后台运行与诊断

- `GET /api/v1/background-tasks/runs/{run_id}` 按持久化账本主键读取，是任务结果的统一入口。
- diagnostics 从同一账本返回跨任务最近运行和可恢复失败对象，是自动化与诊断界面的事实资源；新增任务无需加入后端白名单。metrics 返回聚合指标。
- diagnostics 只根据明确存在的解析失败、分发失败、来源失败和 task state 错误表达待处理对象，不根据统计或状态名称猜测失败对象；消息盒子使用独立持久化 contract。
- 后台任务成功或失败落盘后发布 `background_task_updated`；支持流式响应的客户端将它与内容、队列和分发事件一起视为 diagnostics 刷新提示，重新读取事实资源，而不是直接相信事件 payload。Web 客户端当前使用带鉴权头的请求，无法依赖浏览器原生 `EventSource`，因此在界面实际使用诊断数据时以 5 秒刷新作为兜底。
- 通用响应稳定表达 `run_id`、任务类型、状态、开始/结束时间、错误、`metadata`、`result` 和只读 `presentation`；触发来源、关联平台/内容/来源/队列项等任务特定输入只位于 `metadata`，不再作为未声明的顶层字段。
- `presentation` 由后端按 task type 从持久化事实投影，包含 `kind`、`title`、`summary`、`error_code`、`entity_links`、`allowed_actions` 和 `result_sections`。导航动作只指向现有产品路由，不代表通用 mutation 权限；原始 payload 仍是诊断依据。
- 解析、重新解析、摘要、语义索引、发现、同步、分发和连通性测试使用同一 run 观察模型，但结果 payload 仍按任务类型解释。
- 账本按任务保留最近 200 条；它记录观察结果，不承诺执行恢复或自动重放。

收藏同步、内容处理、语义索引、发现、分发、连通性和 Bot 群组同步已有业务化 renderer contract；未知 task 不会凭字段名猜测重试动作。

## 消息盒子

- `GET /api/v1/notifications` 返回持久化消息、筛选后的总数和全局真实未读数。
- `POST /api/v1/notifications/{notification_id}/actions` 持久化已读、静默、稍后提醒、移除和恢复状态；`snooze` 必须提供未来的 UTC 时间。
- `POST /api/v1/notifications/read-all` 只处理当前未过期、未静默、未移除且不在稍后提醒期内的未读消息。
- `POST /api/v1/notifications/digest` 立即从持久化动态候选和进行中知识事件变化生成一次事实摘要；空窗口不创建消息。
- 后台失败会进入消息盒子；只有用户主动触发的成功运行产生完成回执。重复失败按任务和关联对象合并，调度成功仍只保留在 run ledger。
- Agent 高风险确认在等待期间进入消息盒子并深链到所属会话；Telegram Bot 来源以 `bot_agent_confirmation` 保留 origin；批准、拒绝、失败或取消后保留审计记录，但从活动消息中移除。
- leader 周期任务按用户设置的启用状态和间隔复用同一摘要生产者；它不调用模型，也不把空窗口写成占位消息。
- `notification_updated` 是刷新提示，不是消息事实；完整 contract 见 `../modules/notification-inbox.md`。

## 健康与能力

- `/health` 与 `/api/v1/health` 返回同一健康结构。
- 健康检查区分数据库、队列、FTS、worker、模型供应商和后台任务状态。
- `GET /api/v1/ai/capabilities` 描述配置与能力，不执行真实模型请求。
- `POST /api/v1/ai/connectivity-test` 执行真实连通性测试并记录 `run_id`。
- AI 连通性响应稳定包含 `run_id`、`target`、`status`、`ok` 和 `elapsed_ms`，供应商相关结果或错误按目标落在明确可选字段；`POST /api/v1/ai/models` 返回目标与模型名列表。
- `POST /api/v1/platform-health/parse-test` 执行只读真实解析测试，不创建收藏内容、不推进同步 cursor。它与生产解析共用数据库平台凭据和适配器构造逻辑；成功结果包含内容/布局类型、作者字段、封面与媒体、正文长度、发布时间、统计、来源标签，以及结构化扩展和私有归档的键名，便于区分“请求成功”与“字段完整”。响应不返回 Cookie 或完整原始平台 payload。
- 平台解析测试无论业务成功或失败都返回同一个具名诊断响应，并保留 `run_id`、平台、耗时和显式 `ok/status/error`；HTTP 失败仍按公共错误规则处理。

“已配置”“健康检查通过”“真实业务调用成功”是三个不同层级，界面不得合并为一个布尔状态。

## SSE 事件

- `GET /api/v1/events/subscribe` 提供通用事件流，`/events/health` 提供事件系统健康状态。
- 当前事件用于提示内容变化、后台任务状态、分发结果、队列变化和 Bot 同步进度。
- 事件总线采用进程内广播与 SQLite outbox 轮询同步，以支持多实例传播。
- SSE 是刷新提示而不是完整事实源；客户端收到事件后应按需重新读取对应资源。

## 知识事件

- `GET /api/v1/knowledge-events` 分页读取事件，可按事件状态或成员内容过滤。
- `POST /api/v1/knowledge-events` 以至少一条真实内容创建人工事件。
- `GET/PATCH /api/v1/knowledge-events/{event_id}` 读取或更新标题、说明与进行中/已解决/已归档状态。
- `/api/v1/knowledge-events/{event_id}/members` 及成员路径负责加入、分类和移除内容；同一内容不能重复加入，事件不能移除最后一条成员。
- 成员显式记录内容角色、证据状态、关系说明和 `manual|agent` 加入来源；响应保留原内容 ID、URL、标题、摘要与发生时间。
- `knowledge_event_created` 与 `knowledge_event_updated` 只提示客户端刷新，不携带可替代详情响应的事件事实。

当前 contract 只提供确定性页面操作和经用户确认的 Agent 显式事件组织，不宣称自动聚类、合并/拆分建议或模型综合已经实现。

## 鉴权与错误

- API token 只通过 `X-API-Token` 或 Bearer header 传递，不放入 URL query。
- 业务错误应使用稳定错误码和明确 HTTP 状态，不应只返回自由文本。
- 写操作返回 `run_id` 时必须说明它代表受理、调度还是已经执行。
