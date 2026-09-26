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

Agent service 构建上下文消息，注册内置工具，运行模型，记录 tool calls、confirmations、runs 和 messages。确认是持久化资源：等待项同时投影到消息盒子，页面可按 session 恢复；停止 run、清空或删除 session 会取消其待确认项。工具完成或失败后，`tool` 消息引用调用记录中的结构化结果，刷新会话后仍能恢复来源与错误，而不是只依赖当次 SSE。

会话清空与软删除都是同步动作，统一返回 `AgentSessionActionResponse`；成功响应只确认目标 session 已处理，不虚构后台 run。

`search_content` 复用 `UnifiedSearchService`，分组返回收藏内容、人工知识事件和经过媒体资产归属、类型、秒数及已知时长校验的音视频时间点。每条证据都有稳定内部 `route`；平台与起止时间只过滤内容及其衍生时间点，知识事件保持独立事件域语义。参数中的平台值和 ISO 时间由工具 schema 校验，不再把不存在的单数 `platform` 参数传入 embedding service。

`read_content` 读取存档正文或指定秒数区间的时间片，不返回媒体签名和庞大原始元数据。它同时返回当前内容 `status`；只有 `parse_failed` 时返回持久化的 `parse_error`（`message` 最多 2000 字符、`type` 最多 200 字符、`at` 为 UTC 时间），其他状态为 null。`capture_content` 与 QQ 持久回执共用相同错误投影，避免只有失败状态却看不到实际原因。解析诊断先核对原始错误，不能把 `waiting_parse`、下游摘要/索引缺密钥当成解析根因，也不能按平台猜测登录态、反爬或 HTTP 状态码。字幕从当前内容已校验的媒体资产关联中读取，返回完整片段文本、平台生成标记、起止秒数、可点击 route 和下一页 offset；不受通用 api_get 前 20 个数组元素的截断限制。正文每页 12000 字符，时间片每页默认 10、最多 30 条；超长片段明确标记 text_truncated。

无时间范围的 `read_content` 同时返回最多 100 张非头像图片的资产 ID、顺序与说明，超限明确标记。`read_image` 校验图片属于指定收藏，再读取 ready 的本地原图/优化变体，经过文件大小、像素和存储根目录校验后交给配置的视觉模型。每次一张，最多 10 MiB / 2000 万像素，发送前等比例缩至 2048 像素边长并转换 JPEG；动图只读取首帧。没有有效归档时返回明确错误，不绕过归档策略抓取远端。

图片识别返回 generated=true、source_kind=model_image_reading、模型名称和收藏链接，通过已有工具消息持久化；不覆盖正文、不冒充来源原文，也尚未写入语义索引。图片数据、存储路径与媒体签名不进入工具结果，外部模型异常统一转为结构化错误，避免回显请求数据。

模型动态调用在 LangGraph 内部替换“步骤不足”响应之前检查剩余步骤：预算不足但仍请求工具时抛出结构化 agent_step_limit_reached，并由既有失败流程保存 failed 状态，不将占位文本当作完成回答。不依赖英文错误文案匹配。

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

## 历史决策

- [已关闭问题的历史决策](../../issues/archive/README.md)。

## 尚未实现 / 计划扩展

真实模型流式运行、Bot 自然语言模型调用和跨场景轻量 Agent 仍需按系统构想继续验收；当前捕获工具只覆盖单链接和单段文字，事件工具只覆盖显式创建与加入成员，不覆盖附件、media group、自动聚类、事件合并/拆分、模型综合、模板推断或存储成本决策。本地已闭环的确认、持久化与 Bot 按钮回调不代表真实 Telegram 网络、模型选择工具或回答质量已验收。

确认执行通过数据库 pending 条件更新领取，批准/拒绝/取消相互排斥。批准后先提交工具与 run 的 running 状态再调用副作用；执行中崩溃不会自动重放已领取确认。通用 bridge 拒绝点段、百分号编码、重复斜杠、内嵌 query/fragment 与反斜杠，query 必须通过独立参数传入。


## 同一轮工具并发与失败事务（2026-09-10）

真实 DeepSeek 一轮产生多个检索调用时，LangGraph 会并发调度。工具共享该轮 AsyncSession，因此工具包装器按轮次串行执行完整工具数据库操作，避免并发 flush。开始调用模型前先提交 run 和用户消息；数据库事务失败后先 rollback、重新读取已持久化 run，再保存失败状态，避免错误处理中再次触发 PendingRollbackError。不同运行不共用此锁。

执行工具前提交 running 账本，避免远端读取期间占用 SQLite 写锁；成功或结构化失败的工具结果与工具消息在返回模型前提交，下一轮模型等待不阻塞其他写入。确认请求也在返回模型前持久化，确认领取仍由原有数据库条件更新保护。此边界不替代工具内部自身的事务设计。

工具抛错时先回滚未完成事务，再按调用前保存的 ID 重新读取运行、会话和工具账本，写入 failed 与错误消息。包括 flush 完整性错误在内的失败不会在失效事务上再次 flush；工具已独立提交或已发生的外部副作用不由这个回滚撤销。

针对此前真实回答偏长，提示词补充简单问题一两句、来源链接嵌入句中、不主动报告检索过程/工具或模型名称、生成来源只标注一次等输出要求。该调整已加载，但新一轮真实模型复验被自动审批拒绝，尚不能声称简洁性已改善。

## PDF 原页证据（2026-09-10）

search_content 增加 document_pages（包含文件名、media_asset_id、page_number、excerpt 和 route）。read_content 使用 document_asset_id 与 page_number 成对定位当前资产原页，不能同时传媒体时间段；每次最多返回 12000 字符，next_offset 支持继续读取。普通读取列出文件与提取状态，不能把无原生文本页面当作已识别。前端文档引用卡片保留同一文件与页码；真实 DeepSeek 已完成一个自制 PDF 指定页的价格问答，回答 128 元并附正确页码 route，工具及回答已持久化；开放式多文档问答质量仍待验收。

read_content 的 segments 每项返回经过归属/时长校验的 media_asset_id，供前端建立时间点引用；普通正文读取同时提供内容引用。

多来源模型综合现由[默认关闭的周期工作流](content-aggregation.md)实现，产物仍可由既有内容检索/读取和事件工具访问。Agent 没有新的隐式模型执行或推送授权。push_batch 遵守聚合推送开关，不重置正在发送的队列项，排期使用数据库状态条件更新。

## QQ 私聊入口（2026-09-26）

Koishi 管理员私聊通过 `/bot/qq/{config_id}/agent` 调用同一个 `AgentService`；会话按 `qq-{config_id}-{user_id}` 绑定；网页删除后创建新代次会话而不恢复旧历史，人设由 `qq_bot_agent.persona` 追加，不另建聊天 Agent。后端同时校验 API token、启用中的 QQ Bot 配置、`qq_bot_agent.enabled` 与 `admin_qq` 白名单。群消息不能作为该入口的请求字段提交。

入口保存原消息 ID、文字、有序链接（包括重复位置）、引用和转发、附件来源；模型只看到材料引用及文件名，附件下载签名不进入模型上下文。最近十条用户消息的材料可继续被指代；目标不明确时需澄清。`capture_content` 的 `source_ref` 与可选 `text_selection` 只在服务器建立的 QQ 上下文中解析，文字选区必须是原文连续子串，QQ 不能借模型生成的 URL 或文字保存。收藏记录的 `ContentSource` 保留 `qq_bot`、来源消息、run 和材料引用。

管理员明确要求的保存、无其他指令的独立链接/转发/附件分享，通过入口策略授权收藏，不再次弹确认；普通聊天和明确排除的材料不自动保存，是否保存及指代范围由同一个 Agent 根据输入理解。其余写操作仍创建正式 confirmation。独立回复“确认/同意/执行吧/取消/拒绝”等且当前只有一项待办时，由后端直接调用 confirmation decision，不让模型选择确认 ID；引用消息尚未绑定确认回执时只展示待办，不执行。

同一 Bot/管理员/QQ 消息 ID 对应唯一 run，平台重报复用回执，不重复模型与写操作。回执从工具账本及 `ContentSource.run_id` 恢复，涵盖内容已提交但工具结果尚未提交的中断。运行中断不自动重放。链接保存复用原解析队列，最多等待三十秒以支持本轮继续读取；GET 回执读取最新解析状态。附件仅从 QQ CDN 下载，禁止重定向和内网地址，单件最多 32 MiB 且不超过系统上传限额，复用文件捕获和本地存储，不承诺 OCR/转写。

QQ 真实模型验收发现过“未调用工具却回复已保存并编造收藏 ID”的情况。上下文还原现保留持久工具调用及结果，按合法的 AI 调用／ToolMessage 成对传给模型，不再只保留用户与助手文案。QQ 终答中的收藏链接必须来自本轮成功工具结果或已提交的捕获；没有任何执行证据却直接以“已保存”等肯定完成语开头时，在同一个 run 内最多补一次工具纠错，仍无证据则保存失败状态，不提交虚假成功回复。否定陈述、引用原文和本轮读取证实的历史收藏不当作新写入声明；该校验不从用户文字关键词决定是否收藏。
