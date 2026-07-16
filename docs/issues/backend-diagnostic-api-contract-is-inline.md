# 诊断和动作型 API 返回 contract 依赖 inline dict

## 状态

active

## 处置说明

本轮暂不变更 AI、Agent 与 RAG 实现；该问题保留为活动 issue，待其他基础治理完成后单独设计和修复。

## 现象

- AI connectivity、platform parse test、favorites sync trigger/retry、discovery source test/sync、distribution queue 多个动作 endpoint 返回 inline dict，缺少统一 response model。
- `docs/backend/api/endpoints.md` 能列出 endpoint，领域分册能解释行为，但当前 OpenAPI 文档检查主要证明路径覆盖，不能证明返回字段、错误 envelope、`run_id` 语义和前端一致。
- 前端多个位置只能用 `data['run_id']`、`status == "accepted"`、动态 map 或弹层各自解释动作结果。

## 影响范围

- 后端模块：config-system、favorites-sync、discovery、distribution、events-tasks。
- 前端页面：动态页、自动化页、内容详情页、任务结果页、Agent 工作台。
- 数据：background task run、动作结果、错误 payload。
- 用户影响：成功/失败展示、任务跳转、重试按钮和 Agent API bridge 容易因为字段漂移而失效。

## 复现方式

1. 搜索 `backend/app/routers` 中没有 `response_model` 的 `@router.post` 动作 endpoint。
2. 查看 `system.py`、`discovery.py`、`distribution_queue.py` 中的 `return {"status": ...}`、`return {"run_id": ...}` 等 inline dict。
3. 对照前端调用处，确认字段解析通常依赖动态 map。

## 根因分析

- Router 直接构造响应，schema 分散在实现、手写 API 文档和前端调用代码之间。
- 动作型 API 没有统一 `accepted/run_id/policy/error/details` response contract。
- OpenAPI 校验没有覆盖关键 response schema，使“路径存在”被误当作“contract 稳定”。

## 关联代码

- `backend/app/routers/system.py`
- `backend/app/routers/discovery.py`
- `backend/app/routers/distribution_queue.py`
- `backend/app/schemas/common.py`
- `scripts/check_openapi_docs.py`

## 关联文档

- `../backend/api.md`
- `../backend/modules/events-tasks.md`
- `../frontend/components/task-result.md`
- `frontend-post-processing-panel-side-effects.md`
- `task-run-result-contract-missing.md`

## 修复建议

- 最小修复：为高频动作 endpoint 补 Pydantic response model，至少稳定 `status`、`run_id`、`message`、`error`、`policy`、`details` 字段。
- 中期修复：统一动作型 API 的成功/失败 envelope，并明确哪些接口返回 background run。
- 长期修复：扩展 OpenAPI docs check，校验关键 endpoint 的 response schema 名称或字段集合。

## 验证方式

- 自动测试：读取 OpenAPI schema，断言关键动作 endpoint 的 `response_model` 不为空且字段集合稳定。
- API 测试：覆盖 AI connectivity、platform parse test、favorites sync retry、discovery sync、distribution push now 的成功和失败响应。
- 文档校验：`.venv\Scripts\python.exe scripts\check_openapi_docs.py docs\backend\api\endpoints.md` 并补充 response schema 校验。
