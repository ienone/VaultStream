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
- 内容与知识事件的统一分组搜索；事件可人工创建，也可来自自动聚合。
- 命中内容的人物/主题聚合，以及带显式媒体资产和秒数的章节/转写时间点。

## 不承担职责

- 不管理内容入库。
- 不直接执行平台抓取。
- 不替代 Agent 对话体验。

## 实现逻辑

内容入库后按配置生成摘要和语义 chunk，写入 `content_embeddings`。自动索引由 `enable_auto_semantic_indexing` 统一约束，关闭时 post-ingest 在创建 background task run 和调用 embedding provider 前停止；已有索引读取与用户显式发起的重建/失败重试不受该自动化开关影响。异步生成向量期间如果内容已被删除，索引任务在持久化前重新核对内容存在性并以 `indexed=false` 正常终止；提交阶段的删除竞争也按同一语义处理，不写孤立 embedding、不产生虚假失败通知。`GET /search/unified?mode=semantic` 在存在当前模型签名的有效索引时执行向量召回，同时执行 SQLite FTS5/LIKE 召回，并用 RRF 合并；无当前索引时退化为关键词召回。返回的 `match_source` 明确区分 `vector`、`fts` 和 `hybrid`。

收藏列表、全局搜索和 Agent 共用 unified service。关键词模式与空内容查询调用 ContentRepository 分页，不触发 embedding。`build_conditions` 统一平台、状态、原子标签、作者、创建时间和收藏/发现范围；向量、FTS、人物、主题、时间点和文档精确召回均在限制候选数量前应用条件，不再各自维护范围过滤器。关键词分页以创建时间和 ID 降序稳定排序；语义仍为有限 top_k 召回。完整 contract 见 [搜索接口](../api/contents-search-media.md#搜索与语义索引)。

单分块 retry 在响应前完成 provider 调用和持久化，并以 `SemanticEmbeddingRetryResponse` 返回分块最新状态与必需 `run_id`；它不是后台 accepted 响应。

完整内容重建在更新现有单元后，于同一事务清理该内容当前已经不存在的 chunk_index；被删除或撤回的字幕不再因旧向量残留而被召回。清理范围只限该内容，不影响其他收藏。

多分块索引的模型调用阶段禁用该 session 的自动 flush，避免查询下一分块时把先前分块写入 SQLite，并在后续网络等待期间占用唯一写锁。全部分块生成完成后统一写入和清理，维持一次事务提交。此约束针对索引自身的写入，不会释放调用方此前已持有的写事务。

完整索引提交前以读取时的 Content.updated_at 为版本条件执行不改变时间戳的条件更新，取得短写事务后再保存分块，避免模型等待期间原文已修改却提交旧结果。自有 session 遇到版本变化回滚并返回 false；调用方提供 session 时抛出 StaleDataError，调用方须回滚。该门禁不会在模型等待期间持有写锁。单分块 retry 复用同一版本门禁，冲突时回滚并通过正式接口返回 409“原文已变化，请刷新后重新索引”，不计为成功。

正文超过全局概览的 4000 字限制时，额外按 2000 字、相邻重叠 200 字建立完整正文索引；保留原始文本，标题标注字符区间。正文单元使用 -2 起向下的编号，-1 保留给全局概览，非负编号保持原有平台切片语义，不把正文字符区间误当视频时间点。失败重试和重建清理复用统一单元列表，正文缩短后撤销多余单元。已有长文需要重建才能获得新增覆盖，不声称历史索引自动全部更新。

发现同步使用的 `has_current_content_index` 复用重建估算，核验全部当前单元的文本指纹、模型签名和 indexed 状态；只存在一个成功向量不足以跳过补建。内容不存在或未解析成功也不算就绪。该判断不调用模型，不改变自动索引策略开关。

`GET /search/unified` 复用上述内容检索，并独立查询知识事件。事件只搜索事件标题、描述、成员备注和成员内容文本，返回 `title`、`description` 或 `member` 匹配来源；事件没有向量索引时不得标成语义命中。`kind` 可避免调用未请求的结果域，例如 `events` 不执行 embedding 搜索。

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

- `GET /api/v1/search/unified`
- `GET /api/v1/search/semantic/index-status`
- `POST /api/v1/search/semantic/reindex`
- `POST /api/v1/search/semantic/embeddings/{embedding_id}/retry`

## 配置与策略

- embedding 模型、摘要模型、自动语义索引开关和重建成本控制来自系统设置或明确 API contract。
- 自动索引服从 `AutomationPolicyService`；手动重建先返回 dry-run 候选数与预计 embedding 调用数，只有用户显式提交非 dry-run 请求才调度。

## 当前问题

- 向量分支按索引时间降序截取候选行，再在 Python 中计算相似度；默认 `embedding_search_max_rows=5000`，不是全库 ANN。近期多分块会挤占旧材料召回，需按真实规模验证；有全文兜底不代表语义覆盖完整。
- 已有真实 Agent 读取、回答和可点击引用，但尚不足以保证开放式多材料问答、无答案行为和持续质量。判断依据集中在[整体能力评估](../../plans/2026-09-14-product-architecture-review.plan.md#capabilities)。

## 尚未实现 / 计划扩展

混合检索、显式音视频时间点和 PDF 页码定位已实现。[Bilibili 解析](../../../backend/app/adapters/bilibili_parser/video_media.py)生产平台章节/字幕，[文档提取](../../../backend/app/services/document_text.py)生产经过原件校验的 PDF 原生页；摘要保留这些来源片段。[真实验收](../../issues/2026-09-10-real-world-acceptance.md)包含长文末段语义召回、媒体定位、PDF 模型回答与引用点击，不再沿用“所有时间字段和页码问答未实现”的旧判断。

尚缺通用 ASR/OCR、稳定来源修订引用、系统化的召回/拒答质量验证和统一模型使用治理。已有局部样本不能外推为全部平台、任意问题或长期质量；演进见[整体方案](../../plans/2026-09-14-product-architecture-review.plan.md#automation)。

主题与时间点的精确候选在同一 SQLite 查询中应用解析状态、收藏/发现范围、平台和日期后再 LIMIT；不再先截断全库 ID 后二次过滤。

## PDF 页码检索（2026-09-10）

统一检索新增 document_pages 分组：SQLite JSON 文本条件按范围过滤候选，并与向量候选合并，最终重新核对资产及原变体身份后返回页码 route。不是独立页级 FTS，规模性能尚未验收。索引生成前同样验证 PDF 页；提取替换时清除该内容旧索引，随后按既有策略重建。摘要更新保留 PDF 原生页及音视频章节/字幕，模型派生块标记 generated=true；模型等待期间内容版本改变则回滚，不提交旧摘要。PDF 摘要读取通过资产/变体校验的原生页，保存说明单独标识；未完整提取时在摘要前固定标注覆盖限制。没有可读页或尚未提取时返回 409，不将保存说明伪装为文档摘要。

摘要服务不再吞掉模型失败后返回旧 Content。缺失配置、模型异常及空摘要均产生失败回执，异常路径回滚，既有摘要和来源切片保留；自动 post-ingest 仍按既有隔离逻辑继续其他后处理。

摘要成功保存时在同一事务撤销该内容的旧向量索引，防止切片替换后仍召回旧解释；失败时原摘要、原切片和原索引均保留。手动摘要成功后使用既有 PostIngest 自动索引调度，遵循 enable_auto_semantic_indexing；关闭时不调用 embedding 模型，用户仍可显式重建。摘要成功回执不等于索引已完成。

摘要复用按实际提示词（标题、正文/保存说明、校验后的 PDF 原页及覆盖状态）、模型、API 版本和输出 schema 的 SHA-256 判断，成功时保存 summary_source_hash。不以“已有摘要”代替来源版本判断；输入相同且非 force 时不调用模型、不撤销索引，输入或模型变化则重新生成。历史无指纹结果会在下次请求时重新生成一次。此为本地结果复用，不代表供应商 Prompt Cache 命中。
