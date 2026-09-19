# 知识事件模块

## 文档状态

active

## 职责

知识事件是跨内容模板的人工组织视图，不是新的内容类型。模块保存事件标题、说明、状态，以及每条成员内容在事件中的角色、证据状态和关系说明；成员始终链接回 `contents` 原记录。

人工入口支持明确创建、加入、分类、移除、归档和恢复；Agent 在正式写确认后按显式 ID 创建或加入。另有默认关闭的[多来源自动聚合](content-aggregation.md)，只新建待核实事件及 AI 综合稿，不改写已确认边界，不执行自动合并或拆分。

## 调用链

- router：`backend/app/routers/knowledge_events.py`
- schema：`backend/app/schemas/knowledge_event.py`
- service：`backend/app/services/knowledge_event_service.py`
- repository：`backend/app/repositories/knowledge_event_repository.py`
- ORM：`backend/app/models/knowledge_event.py`

router 只负责鉴权、输入验证和稳定错误映射；事件编排位于 service，查询位于 repository。

## 核心约束

- 创建事件至少需要一条真实、未删除的内容。
- 同一内容不能在同一事件中重复出现。
- 事件必须保留至少一个成员；若暂时不再使用，应归档事件，而不是留下无证据事件。
- 成员角色为原始来源、独立报道、评论观点、背景资料、更正信息或现场证据。
- 证据状态为尚未确认、已确认、存在争议或观点；“观点”不能被界面表达为已确认事实。
- 成员来源区分 `manual` 与 `agent`；Agent 只能在写确认后写入 `agent`，不能冒充人工来源。
- 成员增删和分类变化发布 `knowledge_event_updated` 刷新提示，但 API/数据库仍是事实源。
- 成员移除返回命名 `KnowledgeEventMemberRemoveResponse`，明确 event/content ID；事件至少保留一个成员的约束仍由 service 执行。
- 任何事件成员都构成候选 TTL 的持久依赖，不限 `SOURCE` 角色，事件归档后也继续保护成员原内容、来源、索引和成员关系。自动清理不会把证据改成用户采纳状态；只有显式移除成员后，内容才可能在后续清理中重新满足资格。
- 候选清理在 SQLite 短写事务内先取得 writer lock 再检查事件成员；与成员写入串行后，清理只能看到加入前或加入后的完整状态，不会在先查后删窗口级联丢失新成员。用户主动不可逆擦除仍是独立流程。

## 验证

- 当前长期回归只保护最后成员约束及并发删除。创建、分类、恢复和 Agent 组织等流程曾完成本地验收，其大范围 mock/CRUD 测试已删除，后续修改时针对性验证。
- m32 在仓库实验数据库建立 `knowledge_events` 与 `knowledge_event_members`；当前 schema gate 版本为 33，后续 m33 用于媒体书签，不改变知识事件表。
- 真实探针通过正式 Agent invoke → confirmation → approve 链路调用 service/repository，在仓库 SQLite 中创建事件并加入第二条内容，验证两条成员均记录 `agent` 来源，结束后清理自身事件、成员、内容和 Agent 会话记录。

上述历史验证仅覆盖人工/Agent 组织。自动综合的当前实现和隔离验证见聚合模块；真实模型质量、合并/拆分和部署不在该证据范围内。

内容删除与直接移除成员共用同一最小成员规则；在 SQLite 写事务内串行化检查与移除，避免两个成员并发删除留下空事件。被阻止时返回 409 `knowledge_event_requires_member`，包括已归档事件。
