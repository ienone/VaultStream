# 后端文档总览

## 文档状态

active

后端代码位于 `backend/app/`，核心栈为 FastAPI、SQLAlchemy async、SQLite、后台任务、平台适配器、媒体处理和推送分发。

## 基础文档

- `api.md`: 当前 API 清单和请求约定，由已删除旧路径 docs/API.md 迁移而来。
- `database.md`: 当前数据库结构说明，由已删除旧路径 docs/DATABASE.md 迁移而来。

## 模块文档

- `modules/contents.md`: 内容创建、解析、详情、后处理状态。
- `modules/media.md`: 本地媒体、图片代理、归档和安全抓取。
- `modules/discovery.md`: 发现源、候选内容、巡逻评分。
- `modules/distribution.md`: 分发规则、队列、推送服务。
- `modules/favorites-sync.md`: 收藏同步。
- `modules/accounts-auth.md`: 浏览器登录、Cookie、平台健康。
- `modules/search-rag.md`: 关键词搜索、FTS、语义索引和 RAG 边界。
- `modules/config-system.md`: 系统配置、能力状态、后台诊断。
- `modules/agent.md`: Agent 服务和工具。
- `modules/events-tasks.md`: SSE、后台任务状态和 run 结果。

## 当前架构约束

- routers 应保持薄层，业务逻辑下沉到 services/repositories/tasks。
- 外部副作用必须有策略边界：同步、推送、Agent 工具、媒体抓取、解析 worker 不应绕过用户可见控制面。
- 暴露给前端的 API 应有对应的前端职责文档和测试。
- 集成/真实平台测试必须标记 `@pytest.mark.integration`。

## 验证命令

后端测试应使用仓库虚拟环境：

```powershell
.venv\Scripts\python.exe -m pytest backend/tests -q -m "not integration"
```
