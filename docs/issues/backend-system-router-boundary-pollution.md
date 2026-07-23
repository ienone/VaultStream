# System router 聚合过多业务域和外部副作用

## 状态

active

## 现象

- `backend/app/routers/system.py` 约 1900 行，不再只是系统状态、设置和诊断 router。
- 同一文件同时承载 dashboard、settings、platform health、AI capabilities/connectivity、平台解析测试、收藏同步 status/preview/sync/retry、后台任务 diagnostics/metrics 等多个业务域。
- 部分 endpoint 在 router 内直接调用 LLM、embedding、平台 adapter、`ContentService.create_share()`、`asyncio.create_task()` 和 background task run 记录。

## 影响范围

- 后端模块：config-system、favorites-sync、accounts-auth、discovery、contents、search-rag、events-tasks。
- 前端页面：动态页、自动化页、设置中的账号与平台分区、任务结果页。
- 数据：系统设置、平台健康、收藏同步 run、失败项重试结果、AI 连通性 run。
- 用户影响：策略检查、错误处理、run 记录和 response contract 分散在 router 内，后续修改任何业务域都可能影响系统诊断接口。

## 复现方式

1. 打开 `backend/app/routers/system.py`。
2. 搜索 `@router.post("/ai/connectivity-test")`、`@router.post("/platform-health/parse-test")`、`@router.post("/favorites-sync/sync")`、`@router.post("/favorites-sync/items/retry")`。
3. 观察这些 endpoint 在同一 router 中直接执行外部调用、创建后台任务或写入内容。

## 根因分析

- `system.py` 被当作“所有系统级入口”的收纳文件，缺少按业务域拆分 router/service 的边界。
- 后端文档约束 routers 应保持薄层，但实际实现把业务编排、外部副作用和响应构造混在 router。
- 收藏同步、AI 诊断、平台解析测试等功能没有独立 service contract，导致前端也倾向于把它们当作系统诊断面板的一部分。

## 关联代码

- `backend/app/routers/system.py`
- `backend/app/services/automation_policy.py`
- `backend/app/tasks/favorites_sync.py`
- `backend/app/services/content_service.py`
- `backend/app/services/background_task_state.py`

## 关联文档

- `../backend/README.md`
- `../backend/modules/config-system.md`
- `../backend/modules/favorites-sync.md`
- `../backend/modules/events-tasks.md`
- `../backend/api.md`
- `frontend-control-policy-gaps.md`

## 修复建议

- 最小修复：为 `system.py` 中各业务域标注 owner，禁止继续新增非系统诊断 endpoint。
- 中期修复：将 AI 连通性、平台解析测试、favorites sync trigger/retry、background diagnostics 分别下沉到对应 service，并按模块拆 router 或至少拆 service façade。
- 长期修复：保留 URL contract 时可以通过 router include/adapter 兼容路径，但业务逻辑必须由模块 service 承担，API 测试只验证 contract。

## 验证方式

- 自动测试：`.venv\Scripts\python.exe -m pytest backend/tests/test_api/test_system.py backend/tests/test_tasks/test_favorites_sync_task.py -q`。
- 结构检查：确认 `system.py` 不再直接调用 LLM、platform adapter、`ContentService.create_share()` 或 `asyncio.create_task()`。
- 手动验收：动态页、平台健康、AI 连通性测试、收藏同步手动触发和重试仍保持原 URL contract。
