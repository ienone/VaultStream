# 诊断和动作型 API 返回 contract 依赖 inline dict

## 状态

archived

## 解决结果

2026-09-06 已按真实 router、service、schema、测试和前端调用逐项收敛当前全部写动作的 2xx 成功响应。具备 JSON 响应的动作使用命名 Pydantic model；`DELETE /distribution-rules/{rule_id}/targets/{target_id}` 保持真实 `204 No Content`，并由独立门禁确保不会意外出现响应体。

覆盖范围包括内容处理与审批、媒体书签、知识事件成员、语义索引、Agent 会话、AI 诊断、平台认证与解析、收藏同步、发现源、分发队列与规则、系统设置、Bot 配置/运行时/chat/heartbeat。没有为了统一外观修改既有状态码，也没有给同步完成动作虚构后台语义。

OpenAPI 文档门禁固定校验 148 条路径和 56 个动作 contract。静态盘点不再存在匿名 2xx JSON 写响应；唯一无 schema 的写成功响应是上述已登记的 bodyless 204。

## 根因与修复

- 原因：router 直接构造 dict，成功响应形状散落在实现、手写文档和前端动态解码中；原 OpenAPI 校验只证明路径存在。
- 后端：依据每个真实返回值补命名 response model，并把状态码与 schema 引用加入 `REQUIRED_ACTION_RESPONSE_MODELS`；无响应体动作进入 `REQUIRED_EMPTY_ACTION_RESPONSES`。
- 前端：会影响用户状态判断的 AI、发现源、Bot 配置和内容运行动作通过 typed result 消费；后端承诺必有 `run_id` 时，缺失会被视为无效服务响应。
- 语义：内容摘要、巡逻评分和语义分块 retry 在 HTTP 返回前已经完成并结算 run；重新解析、收藏同步等明确标为 accepted/scheduled 的动作继续通过任务结果确认最终状态。

跨领域错误 envelope 是否需要进一步统一不属于本问题的关闭条件。它需要先证明现有错误码或调用方存在具体漂移，不能因成功响应已经具名就顺带引入新的泛化包装层。

## 验证

- `backend/tests/test_openapi_action_contracts.py` 对 56 个动作 contract 做 schema/status 回归。
- `scripts/check_openapi_docs.py docs/backend/api/endpoints.md` 输出 148 endpoints covered、56 action contracts verified。
- 各领域 API 测试固定删除、同步完成、异步受理、运行引用及 bodyless 204 的真实 payload。
- 前端内容动作测试固定必需 `run_id` 以及同步/异步提示差异。

## 关联文档

- `../../backend/api.md`
- `../../backend/api/contents-search-media.md`
- `../../backend/api/automation-delivery.md`
- `../../backend/api/agent-system-events.md`
