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

Agent service 构建上下文消息，注册内置工具，运行模型，记录 tool calls、confirmations、runs 和 messages。确认是持久化资源：等待项同时投影到消息盒子，页面可按 session 恢复；停止 run、清空或删除 session 会取消其待确认项。工具完成或失败后，结构化结果也作为 `tool` 消息保存，刷新会话后仍能恢复来源与错误，而不是只依赖当次 SSE。

会话清空与软删除都是同步动作，统一返回 `AgentSessionActionResponse`；成功响应只确认目标 session 已处理，不虚构后台 run。

`search_content` 复用 `UnifiedSearchService`，分组返回收藏内容、人工知识事件和经过媒体资产归属、类型、秒数及已知时长校验的音视频时间点。每条证据都有稳定内部 `route`；平台与起止时间只过滤内容及其衍生时间点，知识事件保持独立事件域语义。参数中的平台值和 ISO 时间由工具 schema 校验，不再把不存在的单数 `platform` 参数传入 embedding service。

`capture_content` 是独立写工具，只接受一个明确链接或一段原始文字，并复用 `ContentService`、来源记录、统一后处理与捕获回执；链接标题由解析结果确定，不接受会被静默忽略的标题参数。Telegram Bot `/ai` 使用稳定 `tg-*` 会话调用同一 API；待确认响应显示批准/拒绝按钮，回调先核验 Bot 白名单和会话发起人（管理员可代处理），再调用正式 confirmation decision API，后端工具策略仍是最终边界。部分工具通过内部 API bridge 读取或修改系统状态。

`organize_knowledge_event` 是专用写工具，只接受用户或模型明确给出的内容 ID 与事件动作。它可以用一条内容创建事件，或把一条内容加入既有事件，同时保存成员角色、证据状态和关系说明；执行前必须通过正式 confirmation。工具直接复用 `KnowledgeEventService`，成员来源固定记录为 `agent`，不会把 Agent 操作伪装成人工页面操作。成功结果同时返回内容与事件的稳定内部路由，并随 `tool` 消息持久化。

## 测试

长期回归与临时验收边界见 [验证策略](../testing.md)。本模块其余行为在变更时针对性验收，不保留逐方法测试清单。

## 与其他模块交互

- contents/search/tags/stats: 可读；Agent 搜索证据可回到内容、事件或媒体时间点。
- capture_content: 通过 `ContentService` 保存链接或文字；属于 write，执行前必须确认。
- organize_knowledge_event: 通过 `KnowledgeEventService` 显式创建事件或加入成员；属于 write，执行前必须确认。
- favorites-sync/rules/push: 可能触发副作用。
- config-system: LLM 配置和权限策略。

## 对应前端

- `../../frontend/pages/agent.md`

## API 接口

详见 `../api.md` 的 Agent 相关端点。

## 配置与策略

- Agent 模型配置来自系统设置。
- 工具权限包括 read/write/side-effect 风险等级；副作用工具必须经过确认和策略检查。
- 调用工具和 Action API 时不接受客户端自报 `confirmed`；批准必须通过原 confirmation ID 决定。
- 通用 API bridge 的写能力仅包含内容字段更新与卡片审核。收藏同步、分发、外部发送、服务启停、设置和队列写入不属于通用 bridge。
- `push_batch` 即使获得单次确认，也必须服从 `distribution_mode` 暂停策略。

## 当前问题

- 用户控制面与自动化策略修复记录：`../../issues/archive/frontend-control-policy-gaps.md`
- 已关闭的页面状态边界：`../../issues/archive/frontend-agent-page-controller-and-sse-boundary.md`
- 已关闭的 API bridge 权限问题：`../../issues/archive/backend-agent-api-bridge-policy-bypass.md`

## 尚未实现 / 计划扩展

真实模型流式运行、Bot 自然语言模型调用和跨场景轻量 Agent 仍需按系统构想继续验收；当前捕获工具只覆盖单链接和单段文字，事件工具只覆盖显式创建与加入成员，不覆盖附件、media group、自动聚类、事件合并/拆分、模型综合、模板推断或存储成本决策。本地已闭环的确认、持久化与 Bot 按钮回调不代表真实 Telegram 网络、模型选择工具或回答质量已验收。

确认执行通过数据库 pending 条件更新领取，批准/拒绝/取消相互排斥。批准后先提交工具与 run 的 running 状态再调用副作用；执行中崩溃不会自动重放已领取确认。通用 bridge 拒绝点段、百分号编码、重复斜杠、内嵌 query/fragment 与反斜杠，query 必须通过独立参数传入。


## 历史工具消息格式迁移

`init_db` 用 `_migration:agent_tool_message_payload` 标记一次迁移：工具消息中的旧 JSON 或纯文本转入统一 payload，保留原 content 和已有 result/error。前端只解释 payload，已删除 JSON 字符串与纯文本的运行时多路径。此前真实 SQLite 验收确认迁移保留数据且再次执行不改变消息；该一次性验收测试已在后续精简中删除。
