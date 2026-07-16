# VaultStream API 文档

## 文档状态

active

## 文档职责

本文是当前 API contract 的入口。它描述跨领域规则并链接到领域文档，不逐项复制 router 和 schema。

- `api/endpoints.md`：由当前 FastAPI OpenAPI 生成的完整端点清单。
- `api/contents-search-media.md`：分享、内容、后处理、搜索和媒体访问。
- `api/automation-delivery.md`：发现、收藏同步、分发、目标和 Bot。
- `api/agent-system-events.md`：Agent、后台运行、健康检查和 SSE。

请求字段、枚举、响应模型和状态码以 router、schema、service 返回值及 OpenAPI 为最终事实来源。文档与代码冲突时必须修正文档或 contract，不允许调用方猜测兼容。

## 鉴权

所有 `/api/v1/*` 请求支持以下任一请求头：

- `X-API-Token: <token>`
- `Authorization: Bearer <token>`

未配置 `API_TOKEN` 时可跳过鉴权，仅适合受控本地开发。WebSocket/SSE 同样不得把 token 放入 URL query。

## 通用约定

### 资源与动作

- 读取和普通 CRUD 使用资源路径。
- 预览、测试、重试、同步、重建索引和立即推送是显式动作。
- 同一动作存在内容级和队列项级范围时，调用方必须明确选择，不能由前端猜测。

### 后台运行

- 长耗时或外部副作用动作通常返回 `run_id`。
- 返回 `run_id` 只表示已经受理或调度，除非 contract 明确说明同步执行完成。
- 最终状态通过任务结果、领域资源或事件提示后的重新读取获得。

### 错误

- 使用 HTTP 状态表达协议层结果，稳定错误码表达业务原因。
- 错误文本用于展示和诊断，不能成为调用方分支条件。
- 请求 ID、run ID 和关联资源 ID应保留，敏感凭证不得进入错误文本或日志。

### 分页与批量

- 分页接口明确 page/size 或 cursor 语义，不混用。
- 批量写操作必须有数量上限，并返回逐项结果或可观察 run。
- 预览接口不得产生正常业务副作用。

## 变更流程

构造或修改 API 前依次检查：

1. 后端 router 与 request/response schema。
2. service 返回值、错误和副作用。
3. 现有前端 API client 与类型。
4. 相关自动测试。
5. 本入口、领域分册和 OpenAPI 清单。

端点清单生成与校验：

```powershell
.venv\Scripts\python.exe scripts\export_openapi_endpoints.py --out docs\backend\api\endpoints.md
.venv\Scripts\python.exe scripts\check_openapi_docs.py docs\backend\api\endpoints.md
```

## 常见状态码

- `200 OK`：成功读取或同步完成。
- `201 Created`：资源创建成功。
- `202 Accepted`：后台动作已受理，需继续观察 run。
- `400 Bad Request`：请求或业务前置条件不成立。
- `401 Unauthorized`：缺少或无效鉴权。
- `404 Not Found`：资源不存在。
- `409 Conflict`：状态或唯一性冲突。
- `503 Service Unavailable`：所需 worker、平台或供应商当前不可用。
