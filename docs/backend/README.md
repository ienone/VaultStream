# 后端文档总览

## 文档状态

active

后端位于 `backend/app/`，核心栈为 FastAPI、SQLAlchemy async、SQLite、后台任务、平台适配器、媒体处理和推送分发。

## 基础入口

- `api.md`：API 通用约定和领域索引。
- `api/endpoints.md`：OpenAPI 生成并由 CI 校验的端点清单。
- `api/contents-search-media.md`：内容、搜索与媒体 contract。
- `api/automation-delivery.md`：探索、同步、分发与 Bot contract。
- `api/agent-system-events.md`：Agent、任务、健康与事件 contract。
- `database.md`：数据库事实优先级、领域索引和验证入口。
- `database/content-search.md`：内容、来源、搜索与 FTS。
- `database/automation-delivery.md`：任务、设置、分发与 Bot。
- `database/agent.md`：Agent 持久化。

## 模块文档

- `modules/contents.md`：内容创建、解析、详情和后处理。
- `modules/media.md`：本地媒体、图片代理、归档和安全抓取。
- `modules/discovery.md`：发现源、候选内容和巡逻评分。
- `modules/distribution.md`：分发规则、队列和推送。
- `modules/favorites-sync.md`：收藏同步。
- `modules/accounts-auth.md`：浏览器登录、Cookie 和平台健康。
- `modules/search-rag.md`：关键词搜索、FTS、语义索引和 RAG。
- `modules/config-system.md`：系统配置、能力状态和后台诊断。
- `modules/agent.md`：Agent 服务和工具。
- `modules/events-tasks.md`：SSE、后台任务状态和运行结果。

## 阅读规则

- 修改 API：先读 `api.md`，再读对应领域分册、真实 router/schema、客户端和测试。
- 修改模型或查询：先读 `database.md` 和对应数据库分册，再核对 ORM 与实际 schema。
- 修改业务模块：读取对应 `modules/*.md`，但以代码和可重复验证为最终事实。

## 架构约束

- router 保持薄层，业务编排进入 service/task，数据访问进入 repository。
- 外部副作用必须经过用户可见策略和权限边界。
- API 不返回调用方需要猜测的多形态 contract。
- 集成和真实平台测试必须显式标记，不进入默认测试。

## 验证命令

```powershell
.venv\Scripts\python.exe -m pytest backend/tests -q -m "not integration"
.venv\Scripts\python.exe scripts\check_openapi_docs.py docs\backend\api\endpoints.md
```
