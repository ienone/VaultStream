# 后端模块：搜索、语义索引与 RAG

## 文档状态

active

## 代码位置

- Router: `backend/app/routers/search.py`
- Embedding: `backend/app/services/embedding_service.py`
- Unified search: `backend/app/services/search_service.py`
- Knowledge-event query: `backend/app/repositories/knowledge_event_repository.py`
- Summary: `backend/app/services/content_summary_service.py`
- Database FTS: `backend/app/core/database.py`

## 功能

- 关键词搜索和 FTS。
- 语义搜索。
- 内容摘要和 RAG chunk 生成。
- 语义索引状态、重建和失败 embedding 重试。
- 内容与人工知识事件的统一分组搜索。
- 命中内容的人物/主题聚合，以及带显式媒体资产和秒数的章节/转写时间点。

## 不承担职责

- 不管理内容入库。
- 不直接执行平台抓取。
- 不替代 Agent 对话体验。

## 实现逻辑

内容入库后按配置生成摘要和语义 chunk，写入 `content_embeddings`。自动索引由 `enable_auto_semantic_indexing` 统一约束，关闭时 post-ingest 在创建 background task run 和调用 embedding provider 前停止；已有索引读取与用户显式发起的重建/失败重试不受该自动化开关影响。异步生成向量期间如果内容已被删除，索引任务在持久化前重新核对内容存在性并以 `indexed=false` 正常终止；提交阶段的删除竞争也按同一语义处理，不写孤立 embedding、不产生虚假失败通知。`GET /search/semantic` 在存在当前模型签名的有效索引时执行向量召回，同时执行 SQLite FTS5/LIKE 召回，并用 RRF 合并；无当前索引时退化为关键词召回。返回的 `match_source` 明确区分 `vector`、`fts` 和 `hybrid`。

单分块 retry 在响应前完成 provider 调用和持久化，并以 `SemanticEmbeddingRetryResponse` 返回分块最新状态与必需 `run_id`；它不是后台 accepted 响应。

`GET /search/unified` 复用上述内容检索，并独立查询人工知识事件。事件只搜索事件标题、描述、成员备注和成员内容文本，返回 `title`、`description` 或 `member` 匹配来源；事件没有向量索引时不得标成语义命中。`kind` 可避免调用未请求的结果域，例如 `events` 不执行 embedding 搜索。

人物和主题是可导航的内容字段聚合，不是新实体。候选同时来自混合内容检索和 `author_name` / `tags` 精确字段召回，因此直接查询作者或标签时不依赖 embedding。时间点只从命中的 `rich_payload.chunks[]` 提取：切片必须声明 `segment_type=chapter|transcript`、`media_asset_id` 和 `start_seconds`，可选 `end_seconds`；搜索和内容详情共用同一个校验器，核验资产属于该内容、媒体类型是 audio/video、区间合法且起点未越过已知时长。查询明确命中切片文本，或向量召回明确命中该 chunk 时才返回；发布日期和推断秒数不参与。

Agent 的 `search_content` 直接调用同一 unified service，并把内容、事件和时间点投影为带内部 `route` 的分组证据；平台与创建时间过滤透传到 embedding 和精确字段/时间点候选，不复制一套 Agent 专用检索判断。事件是独立结果域，不受内容过滤影响。

## 测试

长期回归与临时验收边界见 [验证策略](../testing.md)。本模块其余行为在变更时针对性验收，不保留逐方法测试清单。

## 与其他模块交互

- contents: 来源正文、媒体引用和摘要。
- config-system: AI 能力、模型和索引策略。
- agent: Agent 可使用搜索工具读取内容、人工事件和媒体时间点证据。

## 对应前端

- 收藏库语义搜索与全局搜索。
- Agent 工作台。
- 内容详情后处理状态。

## API 接口

- `GET /api/v1/search/semantic`
- `GET /api/v1/search/unified`
- `GET /api/v1/search/semantic/index-status`
- `POST /api/v1/search/semantic/reindex`
- `POST /api/v1/search/semantic/embeddings/{embedding_id}/retry`

## 配置与策略

- embedding 模型、摘要模型、自动语义索引开关和重建成本控制来自系统设置或明确 API contract。
- 自动索引服从 `AutomationPolicyService`；手动重建先返回 dry-run 候选数与预计 embedding 调用数，只有用户显式提交非 dry-run 请求才调度。

## 当前问题

- 无单独 active issue；当前实现仍以搜索模式为主，不能描述为完整 RAG 问答。

## 尚未实现 / 计划扩展

混合检索和显式音视频时间点定位已经实现，但本轮没有验证真实 embedding 模型的召回质量，当前解析/摘要流程也不生产转写或章节时间字段。带稳定引用的问答、PDF 页码定位、转写生产和统一模型调用治理尚未形成完整 RAG 闭环；开始这些功能切片前，需要重新核对数据规模、评估集和当前实现。

主题与时间点的精确候选在同一 SQLite 查询中应用解析状态、收藏/发现范围、平台和日期后再 LIMIT；不再先截断全库 ID 后二次过滤。
