# 07 — RAG 增强向量搜索：完整落地指南

> 生成日期：2026-04-07  
> 状态：功能半实现，存在多处静默失败与设计缺陷  
> 覆盖范围：后端 Python（5个文件）+ 前端 Flutter（2个文件）

---

## 一、当前实现状态速览

这是一个**已经搭建了骨架但骨架有裂缝**的功能。核心链路存在，但在几个关键节点上存在静默失败，导致向量搜索在实际使用中的命中率远低于设计预期。

```
理想链路：
  URL提交 → 解析 → AI摘要+切片 → 向量索引 → 混合检索

实际状态：
  URL提交 → 解析 → AI摘要+切片 ✅
                        ↓
               [配置绕过 🔴] [模型硬编码 🔴]
                        ↓
              向量索引(fire-and-forget) ⚠️
                        ↓
               [Discovery内容跳过 🔴]
                        ↓
              混合检索(全表扫描) ⚠️
                        ↓
               [前端过滤器降级 🟡] [SSE双路冲突 🟡]
```

---

## 二、问题全景图（按层次）

### 2.1 后端问题

| 编号 | 层次 | 严重性 | 问题 | 文件 |
|---|---|---|---|---|
| B1 | 摘要生成 | 🔴 | `os.environ` 直读 API Key，绕过配置层，UI 修改的 Key 对摘要服务无效 | `content_summary_service.py:71` |
| B2 | 摘要生成 | 🔴 | 模型名称硬编码 `"gemini-3.1-flash-lite-preview"`，与 Embedding 服务配置脱节 | `content_summary_service.py:110` |
| B3 | 摘要生成 | 🟡 | `SemanticChunk` / `ContentIntelligence` 在 summary 和 embedding 两个服务中各自定义，`rich_payload["chunks"]` 是无 schema 约束的隐式契约 | `content_summary_service.py:14` / `embedding_service.py`（已删除但逻辑仍依赖） |
| B4 | 向量索引调度 | 🔴 | `asyncio.create_task` 完全 fire-and-forget，无 `done_callback`，无状态追踪，Gemini 不可用时静默丢失 | `tasks/parsing.py:_schedule_embedding_index` |
| B5 | 向量索引调度 | 🔴 | Discovery（RSS/Telegram）内容以 `PARSE_SUCCESS` 直接入库，**永远不触发向量索引** | `tasks/discovery_sync.py` |
| B6 | 向量索引执行 | 🟡 | 每个 chunk 都 `new genai.Client(api_key=api_key)`，N 个 chunk = N 次客户端实例化和潜在的 N 次 TCP 连接 | `embedding_service.py:_embed_text:451` / `_embed_multimodal:210` |
| B7 | 向量索引执行 | 🟡 | 每次 `_upsert_embedding` 调用 `_get_document_embedding_signature()`，内部 3 次 `get_setting_value()`（model + api_key + dim），N 个 chunk = 3N 次 settings 读 | `embedding_service.py:_upsert_embedding:150` |
| B8 | 向量搜索 | 🟡 | `_vector_rank_ids()` 将所有 `ContentEmbedding` 行全部加载进 Python 内存，用 numpy 逐行点积。无 ANN 索引，O(N) 随库增长 | `embedding_service.py:_vector_rank_ids:331` |
| B9 | 向量搜索 | 🟡 | `_cosine_similarity()` 中 `length = min(len(a), len(b))` 允许不同维度向量混合计算，切换模型后旧向量产生垃圾分数 | `embedding_service.py:527` |
| B10 | 模型切换 | 🟡 | 模型切换后无重建索引的 API 或触发机制，旧维度向量与新维度查询向量混用 | `routers/search.py` 缺失 `/reindex` 接口 |
| B11 | 配置一致性 | 🔴 | 摘要服务和向量服务共用 `embedding_api_key` 这个 key 名，但读取路径不同（一个读 env，一个读 settings cache），且摘要用的实际是独立的 generative 模型而非 embedding 模型，混用配置 key 语义混乱 | `content_summary_service.py:75` |

### 2.2 前端问题

| 编号 | 层次 | 严重性 | 问题 | 文件 |
|---|---|---|---|---|
| F1 | 搜索模式切换 | 🟡 | 语义搜索失败时静默 fallback 到关键词搜索（`on DioException { // 回退 }`），用户无任何提示，无法区分"无结果"和"服务不可用" | `collection_provider.dart:276` |
| F2 | 语义搜索结果映射 | 🟡 | `_semanticToShareCard()` 将语义搜索结果转换为 `ShareCard` 时丢弃了 `chunk_index`、`chunk_title`、`match_source`、`score` 字段，命中的语义切片信息无法展示给用户 | `collection_provider.dart:301` |
| F3 | 语义结果过滤降级 | 🟡 | 语义搜索成功返回后，前端再对结果进行本地 `statuses` 过滤（`_matchesSemanticFilters`），但语义搜索 API 返回的 `ShareCard` 缺少 `status` 字段，实际上过滤逻辑硬编码为"只保留 `parse_success`"，不正确 | `collection_provider.dart:346` |
| F4 | 分页语义 | 🟡 | 语义搜索模式下 `hasMore: false`，不支持加载更多，但 `fetchMore()` 不检查当前 `searchMode`，触发后会走关键词分页，混合展示两种结果 | `collection_provider.dart:355` |
| F5 | SSE 冲突 | 🟡 | `CollectionPage.build` 中的 `ref.listen(sseEventStreamProvider)` 在 `content_updated` 时调用 `ref.invalidate(collectionProvider)`，与 Provider 内部精心设计的增量 SSE 更新逻辑互相覆盖。语义搜索模式下 invalidate 会丢失当前搜索状态 | `collection_page.dart:97` |
| F6 | 搜索 UI 可见性 | 🟢 | `CollectionFilterState.isSemantic` getter 存在但 UI 中搜索模式切换入口不明显，用户难以发现向量搜索功能 | `collection_filter_provider.dart:62` |
| F7 | topK 超采样 | 🟢 | 请求时 `requestTopK = semanticTopK * 3`（最大 100），目的是给前端过滤留余量。但后端已按 `top_k` 截断，前端再次 `.take(semanticTopK)` 是多余的一层，逻辑分散且难以维护 | `collection_provider.dart:233` |

---

## 三、分阶段落地方案

### Phase 0：打通基础链路（1周，0 数据库变更）

这一阶段的目标是让现有功能**真正能跑通**，消除静默失败。

---

#### 0-A：统一 API Key 与模型配置读取

**问题**：B1、B2、B11

`content_summary_service.py` 当前：
```python
# 问题：绕过配置层
import os
gemini_key = os.environ.get("GEMINI_API_KEY")
if not gemini_key:
    from app.services.settings_service import get_setting_value
    gemini_key = await get_setting_value("embedding_api_key")

# 问题：硬编码模型
model="gemini-3.1-flash-lite-preview"
```

**修复后**：

1. 在 `system_settings` 中新增两个独立的配置 key：

| Key | 说明 | 默认值 |
|---|---|---|
| `summary_api_key` | 摘要生成专用 API Key（若为空则回退到 `embedding_api_key`） | 空 |
| `summary_model` | 摘要生成模型名 | `gemini-2.0-flash-lite` |
| `embedding_api_key` | 向量嵌入专用 API Key | 空 |
| `embedding_model` | 向量嵌入模型名 | `gemini-embedding-2-preview` |

2. 修改 `content_summary_service.py`：

```python
from app.services.settings_service import get_setting_value

async def generate_summary_for_content(session, content_id, *, force=False):
    # 统一从 settings_service 读取，不再读 os.environ
    api_key = await get_setting_value("summary_api_key") or \
              await get_setting_value("embedding_api_key")
    if not api_key:
        logger.warning("未配置 summary API Key，跳过 AI 分析")
        return content

    model = await get_setting_value("summary_model") or "gemini-2.0-flash-lite"
    
    # 使用读取到的 model，不再硬编码
    response = client.models.generate_content(model=model, ...)
```

3. 在设置页前端新增两个配置项（`automation_tab.dart` 或新的 `ai_tab`）。

---

#### 0-B：修复 Discovery 内容不触发向量索引

**问题**：B5

**修改文件**：`tasks/discovery_sync.py`

```python
# 修改前（在 _sync_single_source 末尾）：
await session.commit()
# 结束，不触发 embedding

# 修改后：
await session.commit()

# 为本次同步新增的内容调度 embedding 索引
from app.services.embedding_service import EmbeddingService
embedding_svc = EmbeddingService()
for content in inserted_contents:  # inserted_contents 需要在插入时收集
    embedding_svc._schedule_embedding_index(content.id)
```

注意：`_schedule_embedding_index` 应在 `EmbeddingService` 上作为公开方法暴露（或提取到模块级函数），避免跨类访问私有方法。

---

#### 0-C：修复前端语义搜索 fallback 的用户感知

**问题**：F1

**修改文件**：`lib/features/collection/providers/collection_provider.dart`

```dart
// 修改前：
} on DioException {
  // 性能/网络兜底：语义检索失败时回退关键词检索。
}

// 修改后：
} on DioException catch (e) {
  // 记录失败原因，并在返回前通知 UI 层
  _lastSemanticError = e;  // 新增字段
  // 回退关键词检索（保留，但让 UI 知道发生了降级）
}
```

同时在 `ShareCardListResponse` 或单独的 provider 中暴露 `semanticSearchFailed: bool` 字段，UI 显示"向量搜索不可用，已切换至关键词模式"提示条。

---

#### 0-D：修复 SSE 双路冲突

**问题**：F5

**修改文件**：`lib/features/collection/collection_page.dart`

删除 `build` 方法中的 `ref.listen(sseEventStreamProvider, ...)` 块（约第 97 行），`Collection` provider 内部已有完整的增量 SSE 处理逻辑，这里的 `ref.invalidate` 是多余且有破坏性的：

```dart
// 删除以下整块：
// ref.listen(sseEventStreamProvider, (_, event) {
//   if (event?.type == 'content_updated') {
//     ref.invalidate(collectionProvider);
//   }
// });
```

---

### Phase 1：建立可靠的索引状态追踪（1-2周，需 1 次数据库迁移）

当前向量索引是"发射后不管"，无法知道哪些内容有索引、哪些失败了。这一阶段建立可观测性。

---

#### 1-A：在 Content 表增加 embedding_status 字段

**新增迁移**：`backend/migrations/m28_add_embedding_status.py`

```python
# 在 contents 表新增字段
ALTER TABLE contents ADD COLUMN embedding_status TEXT 
    NOT NULL DEFAULT 'none' 
    CHECK(embedding_status IN ('none', 'pending', 'indexed', 'failed'));

CREATE INDEX ix_contents_embedding_status ON contents(embedding_status);
```

对应 ORM 模型（`models/content.py`）：

```python
class EmbeddingStatus(str, Enum):
    NONE = "none"        # 未触发
    PENDING = "pending"  # 已调度，进行中
    INDEXED = "indexed"  # 成功
    FAILED = "failed"    # 失败，可重试

class Content(Base):
    # ...
    embedding_status: Mapped[EmbeddingStatus] = mapped_column(
        default=EmbeddingStatus.NONE
    )
```

---

#### 1-B：改造 `_schedule_embedding_index` 为有状态调度

**修改文件**：`tasks/parsing.py`

```python
async def _schedule_embedding_index(self, content_id: int, session: AsyncSession):
    # 1. 先写状态为 pending（在当前事务内）
    content = await session.get(Content, content_id)
    if content:
        content.embedding_status = EmbeddingStatus.PENDING
        await session.flush()  # 不 commit，随外层事务一起提交

    # 2. 调度异步任务，绑定 done_callback
    task = asyncio.create_task(
        EmbeddingService().index_content(content_id)
    )
    task.add_done_callback(
        lambda t: asyncio.create_task(
            _update_embedding_status(content_id, t)
        )
    )

async def _update_embedding_status(content_id: int, task: asyncio.Task):
    async with AsyncSessionLocal() as session:
        content = await session.get(Content, content_id)
        if content is None:
            return
        if task.exception():
            logger.error(f"Embedding failed for {content_id}: {task.exception()}")
            content.embedding_status = EmbeddingStatus.FAILED
        else:
            content.embedding_status = EmbeddingStatus.INDEXED
        await session.commit()
```

---

#### 1-C：在 maintenance.py 中增加失败重试任务

**修改文件**：`tasks/maintenance.py`

```python
async def retry_failed_embeddings():
    """每小时扫描 embedding_status=failed 的内容，触发重试"""
    async with AsyncSessionLocal() as session:
        failed = (await session.execute(
            select(Content)
            .where(Content.embedding_status == EmbeddingStatus.FAILED)
            .limit(50)  # 每批最多 50 条，避免打爆 Gemini 配额
        )).scalars().all()
        
        for content in failed:
            content.embedding_status = EmbeddingStatus.PENDING
            EmbeddingService()._schedule_embedding_index(content.id)
        
        await session.commit()
        logger.info(f"重试 {len(failed)} 条失败的 embedding 任务")
```

---

#### 1-D：提取共享的 RAG schema

**问题**：B3

**新文件**：`backend/app/schemas/rag.py`

```python
from pydantic import BaseModel, Field
from typing import List

class SemanticChunk(BaseModel):
    """语义切片 —— SummaryService 写入，EmbeddingService 读取的契约"""
    title: str = Field(..., description="片段小标题")
    content: str = Field(..., description="片段正文（纯文本）")
    importance: float = Field(default=1.0, ge=0.0, le=1.0)
    media_refs: List[str] = Field(default_factory=list, description="local:// 媒体引用")

class ContentIntelligence(BaseModel):
    """AI 内容理解结果 —— 存入 rich_payload['chunks']"""
    summary: str
    tags: List[str] = Field(default_factory=list)
    rag_chunks: List[SemanticChunk] = Field(default_factory=list)
```

然后在 `content_summary_service.py` 和 `embedding_service.py` 中统一 import：

```python
from app.schemas.rag import SemanticChunk, ContentIntelligence
```

---

### Phase 2：提升向量索引质量（2-3周）

骨架稳定后，提升向量本身的质量。

---

#### 2-A：引入 GeminiClientPool，消除逐 chunk 实例化

**问题**：B6、B7

**新文件**：`backend/app/core/gemini_client_pool.py`

```python
import asyncio
from typing import Optional
from google import genai

class GeminiClientPool:
    """进程级 Gemini client 单例池，按 api_key 缓存"""
    _lock = asyncio.Lock()
    _clients: dict[str, genai.Client] = {}

    @classmethod
    async def get(cls, api_key: str) -> genai.Client:
        if api_key not in cls._clients:
            async with cls._lock:
                if api_key not in cls._clients:  # double-check
                    cls._clients[api_key] = genai.Client(api_key=api_key)
        return cls._clients[api_key]

    @classmethod
    def invalidate(cls, api_key: str):
        """API Key 更新时调用，强制下次重建"""
        cls._clients.pop(api_key, None)
```

**修改 `EmbeddingService._embed_text` 和 `_embed_multimodal`**：

```python
# 修改前：
def _call_gemini():
    client = genai.Client(api_key=api_key)  # 每次 new
    ...

# 修改后：
async def _embed_text(self, text_value, *, task_type):
    # 配置只在 index_content 入口读一次，通过参数传入（见 2-B）
    client = await GeminiClientPool.get(self._current_api_key)
    def _call():
        return client.models.embed_content(...)  # 复用 client
    response = await asyncio.to_thread(_call)
```

---

#### 2-B：批量读取配置，而非每 chunk 读取

**问题**：B7

在 `_index_content_impl` 入口处一次性解析所有配置：

```python
async def _index_content_impl(self, content_id, session, *, own_session):
    # 一次性读取所有配置
    api_key = await self._get_embedding_api_key()
    model = await self._get_embedding_model()
    dim = await self._get_embedding_output_dimensionality()
    model_sig = f"{model}|dim={dim}|task={self._DOCUMENT_TASK_TYPE}"
    
    # 通过 _EmbeddingContext 传入子方法，避免重复 IO
    ctx = _EmbeddingContext(api_key=api_key, model=model, dim=dim, signature=model_sig)
    
    await self._upsert_embedding(session, content_id, -1, "全局摘要", ..., ctx=ctx)
    for chunk in chunks:
        await self._upsert_embedding(session, content_id, idx, ..., ctx=ctx)
```

---

#### 2-C：修复模型切换时的维度混用

**问题**：B9、B10

**修改 `_vector_rank_ids`**（B9 的 `min(len(a), len(b))` 问题）：

当前 `_cosine_similarity` 用的是截断方式兼容不同维度，这会产生错误分数。`_vector_rank_ids` 已经用 `model LIKE pattern` 过滤，但 `_cosine_similarity` 中仍有这行遗留代码。

修复：在行级过滤时直接跳过维度不匹配的向量（已在 `_vector_rank_ids:343` 有 `if len(vec) != len(q): continue` —— 这是正确的），同时彻底删除 `_cosine_similarity` 中的 `min()` 截断：

```python
def _cosine_similarity(self, a: list[float], b: list[float]) -> float:
    if not a or not b or len(a) != len(b):  # 严格要求维度一致
        return float("nan")
    return float(sum(a[i] * b[i] for i in range(len(a))))
```

**新增 `/api/v1/system/reindex-embeddings` 接口**（B10）：

```python
@router.post("/system/reindex-embeddings")
async def trigger_reindex(session: AsyncSession = Depends(get_db)):
    """模型切换后，清空旧向量并触发全量重建"""
    # 1. 删除所有旧 embedding 记录
    await session.execute(delete(ContentEmbedding))
    # 2. 将所有 PARSE_SUCCESS 内容的 embedding_status 重置为 none
    await session.execute(
        update(Content)
        .where(Content.status == ContentStatus.PARSE_SUCCESS)
        .values(embedding_status=EmbeddingStatus.NONE)
    )
    await session.commit()
    # 3. 批量调度（maintenance 任务会捡起 none 状态的内容）
    return {"message": "已清空旧向量，后台重建任务已启动"}
```

---

#### 2-D：前端补全语义搜索结果展示

**问题**：F2、F3、F4

**修改 `ShareCard` 模型**（`models/content.dart`），增加语义搜索专属字段：

```dart
@freezed
class ShareCard with _$ShareCard {
  const factory ShareCard({
    // ... 现有字段 ...
    @Default(-1) int chunkIndex,        // 命中的语义切片索引
    String? chunkTitle,                  // 命中的切片标题
    @Default('keyword') String matchSource, // vector | fts | hybrid
    @Default(0.0) double semanticScore,
  }) = _ShareCard;
}
```

**修改 `_semanticToShareCard`**（`collection_provider.dart`）：

```dart
ShareCard _semanticToShareCard(Map<String, dynamic> row) {
  return ShareCard(
    id: (row['content_id'] as num?)?.toInt() ?? 0,
    // ... 现有字段映射 ...
    chunkIndex: (row['chunk_index'] as num?)?.toInt() ?? -1,
    chunkTitle: row['chunk_title'] as String?,
    matchSource: (row['match_source'] as String?) ?? 'vector',
    semanticScore: (row['score'] as num?)?.toDouble() ?? 0.0,
  );
}
```

**修复 `fetchMore` 在语义模式下的行为**（F4）：

```dart
Future<void> fetchMore() async {
  final filter = ref.read(collectionFilterProvider);
  // 语义模式不支持分页（后端一次返回全部结果）
  if (filter.isSemantic) return;
  // ... 原有分页逻辑 ...
}
```

**修复 `_matchesSemanticFilters` 中的 statuses 过滤**（F3）：

语义搜索返回的 `ShareCard` 没有 `status` 字段，不应在前端做 status 过滤。把这部分过滤逻辑移到后端（在 `_build_content_filters` 中通过 query param 传递），或直接从 `_matchesSemanticFilters` 中删除 `statuses` 过滤：

```dart
bool _matchesSemanticFilters(ShareCard card, {
  List<String>? tags,
  List<String>? platforms,
  // 删除 List<String>? statuses 参数
  String? author,
}) {
  // 删除 statuses 相关的过滤逻辑
  // statuses 过滤已在后端 _build_content_filters 中通过 status query param 处理
  ...
}
```

---

#### 2-E：前端语义搜索 UI 可见性

**问题**：F6、F7

在 `CollectionPage` 的搜索栏增加模式切换按钮（建议放在搜索框右侧）：

```dart
// 搜索框右侧增加切换图标
IconButton(
  icon: Icon(
    filter.isSemantic ? Icons.auto_awesome : Icons.search,
    color: filter.isSemantic ? Theme.of(context).colorScheme.primary : null,
  ),
  tooltip: filter.isSemantic ? '当前：语义搜索（点击切换关键词）' : '当前：关键词搜索（点击切换语义）',
  onPressed: () => ref.read(collectionFilterProvider.notifier)
      .setSearchMode(filter.isSemantic ? 'keyword' : 'semantic'),
),
```

在语义搜索模式下的 `ContentCard` 底部显示匹配来源 badge（`matchSource`: `vector` / `fts` / `hybrid`）和命中切片标题（`chunkTitle`）。

**简化前端 topK 超采样逻辑**（F7）：

```dart
// 修改前：前后端都在控制 topK，逻辑分散
final requestTopK = (semanticTopK * 3).clamp(semanticTopK, 100);
// ... 返回后再 .take(semanticTopK) ...

// 修改后：直接请求所需数量，由后端负责质量控制
final response = await dio.get('/search/semantic', queryParameters: {
  'q': query,
  'top_k': semanticTopK,  // 前端只声明需要几条
  ...
});
// 不再在前端 .take()
```

---

### Phase 3：扩展性（按需，依赖库规模）

当内容达到万级，Phase 2 的 numpy 全表扫描开始成为瓶颈时执行。

---

#### 3-A：引入 sqlite-vec 向量索引（SQLite 路线）

**适用场景**：保持 SQLite，内容量 1万~10万。

`sqlite-vec` 是 SQLite 的向量扩展，提供近似最近邻搜索，无需切换数据库。

```bash
pip install sqlite-vec
```

**修改 `core/db_adapter.py`**：

```python
import sqlite_vec

@event.listens_for(engine.sync_engine, "connect")
def on_connect(dbapi_conn, connection_record):
    dbapi_conn.enable_load_extension(True)
    sqlite_vec.load(dbapi_conn)
    dbapi_conn.enable_load_extension(False)
```

**修改 `models/search.py`**，将向量列改为 sqlite-vec 专用类型（需配合 `vec0` 虚表）：

```python
# 新增虚表（在 init_db 中执行）：
CREATE VIRTUAL TABLE vec_embeddings USING vec0(
    content_id INTEGER,
    chunk_index INTEGER,
    embedding FLOAT[1536]  -- 维度需与配置一致
);
```

**修改 `_vector_rank_ids`**，改为 SQL 查询：

```python
async def _vector_rank_ids(self, *, session, query_vec, filters, limit):
    # 使用 sqlite-vec 的 KNN 查询替代全表扫描
    vec_literal = json.dumps(query_vec)
    stmt = text("""
        SELECT ve.content_id, ve.chunk_index, ve.distance
        FROM vec_embeddings ve
        JOIN contents c ON c.id = ve.content_id
        WHERE ve.embedding MATCH :query_vec
          AND k = :limit
        ORDER BY ve.distance
    """)
    rows = (await session.execute(stmt, {"query_vec": vec_literal, "limit": limit})).all()
    # distance 是 L2，转换为相似度（已标准化则 dot product = cosine similarity）
    return [(r.content_id, 1 - r.distance, r.chunk_index, None) for r in rows]
```

**同步 `_upsert_embedding` 写入虚表**：

```python
# 写入 ORM 表后，同步写入 vec0 虚表
await session.execute(text("""
    INSERT OR REPLACE INTO vec_embeddings(content_id, chunk_index, embedding)
    VALUES (:cid, :cidx, :vec)
"""), {"cid": content_id, "cidx": chunk_index, "vec": json.dumps(vector)})
```

---

#### 3-B：FAISS 内存索引（高并发路线）

**适用场景**：高并发搜索，响应时间敏感，内容量 10万+。

```bash
pip install faiss-cpu
```

`EmbeddingService` 增加 FAISS 索引管理：

```python
import faiss
import numpy as np

class EmbeddingService:
    _faiss_index: Optional[faiss.IndexFlatIP] = None
    _faiss_id_map: list[tuple[int, int]] = []  # [(content_id, chunk_index)]
    _faiss_lock = asyncio.Lock()

    @classmethod
    async def rebuild_faiss_index(cls):
        """进程启动时或重建指令触发时调用"""
        async with AsyncSessionLocal() as session:
            rows = (await session.execute(
                select(ContentEmbedding.content_id, ContentEmbedding.chunk_index,
                       ContentEmbedding.embedding)
                .where(ContentEmbedding.embedding_model.like(f"{current_model}|dim={dim}%"))
            )).all()

        if not rows:
            return

        dim = len(rows[0].embedding)
        index = faiss.IndexFlatIP(dim)  # 内积，等价于标准化后的余弦相似度
        
        vectors = np.array([r.embedding for r in rows], dtype=np.float32)
        index.add(vectors)
        
        async with cls._faiss_lock:
            cls._faiss_index = index
            cls._faiss_id_map = [(r.content_id, r.chunk_index) for r in rows]

    async def _vector_rank_ids_faiss(self, query_vec, limit):
        if self._faiss_index is None:
            return []  # 回退到全表扫描
        
        q = np.array([query_vec], dtype=np.float32)
        scores, indices = self._faiss_index.search(q, limit)
        
        results = []
        for score, idx in zip(scores[0], indices[0]):
            if idx == -1:
                continue
            content_id, chunk_index = self._faiss_id_map[idx]
            results.append((content_id, float(score), chunk_index, None))
        return results
```

**在 `main.py` lifespan 中重建索引**：

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    asyncio.create_task(EmbeddingService.rebuild_faiss_index())  # 异步预热
    yield
```

---

## 四、验收检查清单

完成各 Phase 后，对应检查项应全部通过：

### Phase 0 验收

- [ ] 修改 `system_settings` 中的 `summary_api_key` 后，摘要生成立即使用新 Key（无需重启）
- [ ] 修改 `summary_model` 后，下一次摘要生成使用新模型
- [ ] 新增 RSS 订阅源，同步后内容出现在 `/search/semantic` 结果中
- [ ] 语义搜索失败时，UI 显示降级提示，而非静默变为关键词搜索
- [ ] `CollectionPage` 中删除冗余 `ref.listen` 后，SSE 事件不再触发全量 invalidate

### Phase 1 验收

- [ ] `contents.embedding_status` 字段存在，可查询
- [ ] 解析成功后，`embedding_status` 先变为 `pending`，索引完成后变为 `indexed`
- [ ] Gemini API Key 故意配置错误，索引失败后 `embedding_status` 变为 `failed`
- [ ] 一小时后，`failed` 的内容自动重试，成功后变为 `indexed`
- [ ] `schemas/rag.py` 是 `SemanticChunk` 的唯一定义，两个服务均 import 它

### Phase 2 验收

- [ ] 切换 `embedding_model` 到不同维度的模型后，调用 `/reindex-embeddings` 接口，旧向量被清空
- [ ] 重建完成后，搜索结果不出现 `score: NaN` 或异常低分
- [ ] 语义搜索返回的 `ShareCard` 包含 `chunk_title` 和 `match_source`
- [ ] 语义模式下点击"加载更多"不触发关键词分页请求
- [ ] 搜索框右侧有清晰的搜索模式切换按钮

### Phase 3 验收（sqlite-vec 路线）

- [ ] `EXPLAIN QUERY PLAN` 显示搜索走 `vec_embeddings` 虚表而非全表扫描
- [ ] 1万条内容的库，语义搜索响应时间 < 200ms（P99）

---

## 五、各 Phase 改动文件汇总

| Phase | 改动文件 | 类型 |
|---|---|---|
| 0-A | `backend/app/services/content_summary_service.py` | 修改 |
| 0-A | `frontend/lib/features/settings/presentation/tabs/automation_tab.dart` | 修改 |
| 0-B | `backend/app/tasks/discovery_sync.py` | 修改 |
| 0-C | `frontend/lib/features/collection/providers/collection_provider.dart` | 修改 |
| 0-D | `frontend/lib/features/collection/collection_page.dart` | 修改（删除冗余 listen） |
| 1-A | `backend/migrations/m28_add_embedding_status.py` | 新增 |
| 1-A | `backend/app/models/content.py` | 修改 |
| 1-B | `backend/app/tasks/parsing.py` | 修改 |
| 1-C | `backend/app/tasks/maintenance.py` | 修改 |
| 1-D | `backend/app/schemas/rag.py` | 新增 |
| 1-D | `backend/app/services/content_summary_service.py` | 修改（import） |
| 1-D | `backend/app/services/embedding_service.py` | 修改（import） |
| 2-A | `backend/app/core/gemini_client_pool.py` | 新增 |
| 2-A | `backend/app/services/embedding_service.py` | 修改 |
| 2-B | `backend/app/services/embedding_service.py` | 修改 |
| 2-C | `backend/app/services/embedding_service.py` | 修改 |
| 2-C | `backend/app/routers/system.py` | 修改（新增 `/reindex-embeddings`） |
| 2-D | `frontend/lib/features/collection/models/content.dart` | 修改 |
| 2-D | `frontend/lib/features/collection/providers/collection_provider.dart` | 修改 |
| 2-E | `frontend/lib/features/collection/collection_page.dart` | 修改 |
| 3-A | `backend/app/core/db_adapter.py` | 修改 |
| 3-A | `backend/app/services/embedding_service.py` | 修改 |
| 3-B | `backend/app/services/embedding_service.py` | 修改 |
| 3-B | `backend/app/main.py` | 修改 |
