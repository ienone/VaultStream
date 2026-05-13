# 类型、契约与资源生命周期审计

## 类型契约

### 后端

问题集中在三类：

1. ORM JSON 字段过宽  
   `Content`、`ContentEmbedding` 等模型存在大量 `Mapped[Any]`。JSON 字段适合承载富内容，但需要 Pydantic schema 约束关键结构，例如 `rich_payload`、`media`、`embedding`、`source_metadata`。

2. API 返回 raw dict  
   `backend/app/routers/discovery.py` 使用 `response_model=dict`。这会让 OpenAPI 文档、前端模型、测试断言都失去约束。

3. 测试和实现契约断裂  
   `backend/tests/test_content_summary.py` 导入 `generate_summary_llm`，但当前 service 不再提供该函数。这是最清晰的契约漂移信号。

建议：

- 为 discovery、agent tool result、semantic search、summary intelligence 建立明确 response schema。
- 将 `rich_payload` 中稳定字段拆出 typed model；不稳定扩展字段保留在 `extras`。
- pytest 增加 OpenAPI schema 快照或最小契约测试。

### 前端

问题集中在 Agent 和 Bot 页面：

- `agent_page.dart` 直接解析 raw `Map<String, dynamic>`。
- `bot_management_page.dart` 用 `List<Map<String, dynamic>>` 管理配置。

建议：

- 用 freezed/json_serializable 建立 DTO。
- 对 tool result 采用 sealed union：`SearchResult`、`StatsResult`、`CreateRuleResult`、`PushBatchResult`。
- 后端 tool registry 的 `args_schema` 和 result schema 同步生成或至少在测试中校验。

## 资源生命周期

### Adapter close 缺失

`RssAdapter`、`TelegramAdapter` 持有 `httpx.AsyncClient` 并提供 `close()`。但解析任务创建 adapter 后未统一关闭。建议：

- 让 adapter 实现 async context manager。
- `AdapterFactory.create()` 返回对象后调用方统一：

```python
adapter = AdapterFactory.create(platform)
try:
    ...
finally:
    close = getattr(adapter, "close", None)
    if close:
        await close()
```

更好的方式是让 factory 暴露 `async with AdapterFactory.open(...) as adapter`。

### SSE 生命周期

`frontend/lib/core/network/sse_service.dart`：

- `SseEventBus` 是 static singleton，有 broadcast controllers。
- provider 使用 `@Riverpod(keepAlive: true)`。
- `ref.onDispose` 调用 `_cleanup()`，但没有释放 event bus controller。

这未必会立刻泄露，因为 keepAlive 本身就是长期生命周期，但需要明确 owner：如果 service 是全局常驻，应不要假装随 provider dispose；如果会重建，应释放 controller 并避免旧 listener 残留。

### Browser manager shutdown

`backend/app/adapters/browser/manager.py` 的 shutdown 路径中有线程 join。建议 join 增加 timeout 并在失败时记录明确错误，避免进程关闭卡死。

### 图片代理内存

`backend/app/routers/media.py` 使用 `resp.content` 一次性读取远程图片，再转 WebP 或返回原图。建议改为：

- 先检查 `Content-Length`。
- stream 读取并累计上限。
- 转码前限制像素尺寸和输入大小。

## 错误处理契约

### FTS 静默失败

`text_search.py` 查询 `contents_fts` 失败后返回空列表。由于当前 DB 没有 `contents_fts`，这会把结构缺陷伪装成“没有搜索结果”。建议：

- 缺表时在启动健康检查中暴露 degraded 状态。
- search endpoint 返回 `search_backend: "like_fallback"` 或日志中 emit warning once。
- migration 中补建 FTS 后再移除降级提示。

### Agent tool error

`agent.py` 把 tool 异常转为 500 或 websocket error 文本。建议工具层定义结构化错误码，例如 `invalid_args`、`not_found`、`upstream_failed`、`permission_required`，前端才能做可恢复交互。

