# 05 — 重构优先级路线图

## 优先级矩阵

```
影响面
  高 │ H2(Discovery无向量) │ H1(Embedding无追踪) │ M1(全表扫描)
     │ H3(QR多进程)        │ H4(配置分裂)        │
     │─────────────────────┼─────────────────────│
  中 │ M2(自动审批重复)    │ M3(硬编码模型)      │ M4(EventBus属性)
     │ M5(模型定义重复)    │ M7(inline import)   │ M6(神类ContentParser)
     │─────────────────────┼─────────────────────│
  低 │ M8(Client无复用)    │ M9(无初始化锁)      │ L1-L7(其他)
     └─────────────────────┴─────────────────────┴──────────
       低成本              中成本                高成本
```

---

## P0：立即修复（1-3天，不需要大重构）

这些问题修改代价极低，但影响面大或存在数据风险。

### P0-A：修复 Discovery 内容不触发 Embedding

**文件**：`tasks/discovery_sync.py`

**修改**：在 `_sync_single_source()` 的内容入库并 `commit()` 之后，调用 `_schedule_embedding_index(content.id)` 或等价逻辑。

```python
# 现在（问题代码）：
await session.commit()
# 什么都不做

# 修复后：
await session.commit()
for content in inserted_contents:
    embedding_svc._schedule_embedding_index(content.id)
```

**预期收益**：Discovery 来源的内容（可能是主要内容源）开始出现在向量搜索结果中。

---

### P0-B：修复 content_summary_service 的配置绕过

**文件**：`services/content_summary_service.py`

**修改**：删除 `os.environ.get("GEMINI_API_KEY")` 的直读路径，统一走 `get_setting_value("embedding_api_key")`。

```python
# 删除这段：
import os
gemini_key = os.environ.get("GEMINI_API_KEY")
if not gemini_key:
    ...

# 改为：
gemini_key = await get_setting_value("embedding_api_key")
if not gemini_key:
    logger.warning("未配置 Gemini API Key，跳过摘要生成")
    return
```

---

### P0-C：为 content_summary_service 中的模型名称读取配置

**文件**：`services/content_summary_service.py`

**修改**：将硬编码的 `"gemini-3.1-flash-lite-preview"` 改为从 `settings_service` 读取。

```python
model_name = await get_setting_value("summary_model") or "gemini-2.0-flash-lite"
```

---

### P0-D：将重复的 SemanticChunk 定义提取到共享 schema

**新文件**：`schemas/rag.py`

**内容**：

```python
from pydantic import BaseModel
from typing import Optional

class SemanticChunk(BaseModel):
    title: str
    content: str
    media_refs: list[str] = []

class ContentIntelligence(BaseModel):
    summary: str
    tags: list[str] = []
    rag_chunks: list[SemanticChunk] = []
```

**修改**：`content_summary_service.py` 和 `embedding_service.py` 都改为 `from app.schemas.rag import SemanticChunk, ContentIntelligence`，删除各自的重复定义。

---

## P1：短期改善（1-2周，需要一定重构）

### P1-A：为 Embedding 任务添加状态追踪与重试

**方案**：在 `Content` 表或 `ContentEmbedding` 表增加 `embedding_status` 字段（`pending` / `indexed` / `failed`），并实现一个 `maintenance.py` 中的定时任务扫描 `failed` 状态并重试。

**步骤**：
1. 在 `models/search.py` 或 `models/content.py` 增加字段（需迁移脚本）
2. `_schedule_embedding_index()` 改为先写 `embedding_status=pending`，再 create_task
3. Task 的 `add_done_callback` 中更新状态为 `indexed` 或 `failed`
4. `tasks/maintenance.py` 增加定时扫描 `failed` 的任务，触发重试

---

### P1-B：从 ContentParser 拆出 ArchiveMediaProcessor

**当前问题**：`tasks/parsing.py` 中 `_maybe_process_private_archive_media`、`_apply_stored_mapping_to_record`、`_build_stored_image_mapping`、`_rewrite_text_with_mapping` 共计 >200 行媒体处理代码。

**目标**：新建 `services/archive_media_processor.py`，将上述方法迁移为独立类。`ContentParser` 改为：

```python
processor = ArchiveMediaProcessor(storage_backend)
processed = await processor.process(raw_content)
```

---

### P1-C：合并两处自动审批逻辑

**当前问题**：`tasks/parsing.py:_check_auto_approval()` 和 `services/distribution/engine.py:auto_approve_if_eligible()` 重复实现。

**方案**：在 `services/distribution/decision.py` 中保留唯一的 `auto_approve_content(content, session)` 函数，两处调用方均改为调用此函数，删除各自的实现。

---

### P1-D：修复 EventBus 类属性问题并加锁保护 _last_seen_event_id

**文件**：`core/events.py`

**修改**：
1. 将 `_subscribers`、`_lock`、`_running`、`_poll_task`、`_last_seen_event_id` 全部改为实例属性（在 `__init__` 中初始化）
2. 在 `_poll_remote_events()` 中使用 `async with self._lock:` 保护 `_last_seen_event_id` 的读写
3. `_broadcast_to_local_subscribers` 中对 `put_nowait` 做异常捕获，避免慢消费者导致整体失败

---

### P1-E：修复 QR 认证的多进程问题

**短期方案**：在 Nginx 或进程层用 cookie/session sticky 保证同一用户的 QR start 和 QR poll 落到同一 worker（适合小规模部署）。

**长期方案**：将 `sessions` dict 持久化到 DB（以 `system_settings` 表的 `qr_session_{platform}_{token}` Key 存储），并设置 TTL（5分钟过期自动清理）。

---

### P1-F：EmbeddingService 引入 GeminiClientPool

**文件**：新增 `core/gemini_client_pool.py`

**方案**：

```python
class GeminiClientPool:
    _instance: Optional["GeminiClientPool"] = None
    
    @classmethod
    def get(cls, api_key: str) -> "GeminiClientPool":
        if cls._instance is None or cls._instance.api_key != api_key:
            cls._instance = cls(api_key)
        return cls._instance
    
    def get_client(self) -> genai.Client:
        return self._client  # 复用单例 client
```

`EmbeddingService.index_content()` 开始时解析一次配置（api_key、model、dim），通过 Pool 获取 client，整个索引过程复用。

---

## P2：中长期重构（1个月+，需要架构调整）

### P2-A：统一配置层（ConfigService）

**目标**：消除 `_SETTINGS_CACHE` + `Settings 单例 mutation` + `os.environ 直读` 三种副模式，建立单一的 `ConfigService`：

```python
class ConfigService:
    async def get(self, key: str, default=None) -> Any:
        # TTL cache → DB fallback
        
    async def set(self, key: str, value: Any) -> None:
        # DB 写 → 本地 cache 更新
        # 不再 setattr(settings, ...)
    
    async def get_ai_config(self) -> AIConfig:
        # 一次性读取所有 AI 相关配置，返回类型化对象
```

**迁移策略**：先实现 `ConfigService`，让 `get_setting_value()` 内部代理到它，逐步迁移各调用方。

---

### P2-B：向量搜索引入 FAISS

**当前**：全表扫描 O(N) numpy 点积。

**方案**：在 `EmbeddingService` 中维护内存 FAISS 索引（`faiss.IndexFlatIP` 或 `IndexIVFFlat`），embedding upsert 时同步更新索引。进程重启时从 DB 重建。

**迁移路径**：
1. 引入 `faiss-cpu` 依赖
2. 实现 `_rebuild_faiss_index()` 在 lifespan 中调用
3. `_vector_rank_ids()` 改用 FAISS `index.search()` 替换全表扫描
4. `_upsert_embedding()` 在写 DB 后同步更新 FAISS

---

### P2-C：PatrolService 并发评分

**文件**：`services/patrol_service.py`

**方案**：

```python
# 当前：串行
for content in pending_contents:
    score = await llm.ainvoke(prompt)

# 改为：并发（限制并发度避免速率超限）
semaphore = asyncio.Semaphore(5)
async def score_one(content):
    async with semaphore:
        return await llm.ainvoke(prompt)

results = await asyncio.gather(*[score_one(c) for c in pending_contents])
```

---

### P2-D：ContentParser 完整拆分

在 P1-B 的基础上，进一步拆分剩余职责：

```
tasks/parsing.py（重构后）
  ├── TaskOrchestrator        # 队列 + 重试 + 状态机（~100行）
  └── 委托给：
        ├── AdapterFactory.parse()              # 已存在
        ├── ArchiveMediaProcessor.process()     # P1-B 新增
        ├── SummaryService.generate()           # 已存在
        ├── EmbeddingService.schedule_index()   # 已存在
        └── DistributionDecider.check_auto()    # P1-C 统一后
```

---

## 重构时序建议

```
Week 1: P0（全部4项，代价低、收益高）
  P0-A: Discovery 触发 embedding
  P0-B: 修复 os.environ 绕过
  P0-C: 摘要服务读模型配置
  P0-D: 提取 rag.py 共享 schema

Week 2-3: P1（选最高风险项优先）
  P1-D: 修复 EventBus（低成本高正确性收益）
  P1-C: 合并自动审批逻辑
  P1-F: EmbeddingService 引入 Client Pool
  P1-A: Embedding 状态追踪

Week 4-5: P1（继续）
  P1-B: 拆出 ArchiveMediaProcessor
  P1-E: QR 认证会话持久化

Month 2+: P2（需排期）
  P2-A: ConfigService 统一配置层
  P2-B: FAISS 向量索引
  P2-C: PatrolService 并发评分
  P2-D: ContentParser 完整拆分
```

---

## 验收检查清单

完成重构后，以下问题应全部消失：

- [ ] `content_summary_service.py` 中无 `os.environ.get("GEMINI_API_KEY")`
- [ ] 项目中 `SemanticChunk` 只有一处定义（`schemas/rag.py`）
- [ ] `tasks/parsing.py` < 400 行
- [ ] `EventBus` 无类属性（所有状态在 `__init__` 中初始化为实例属性）
- [ ] Discovery 内容入库后，`content_embeddings` 表有对应记录
- [ ] `_check_auto_approval` 和 `auto_approve_if_eligible` 只保留一处
- [ ] `_embed_text()` / `_embed_multimodal()` 内部不再 `genai.Client()`
- [ ] 向量搜索不再全表扫描（FAISS 或 pgvector）
- [ ] QR 会话状态在多进程部署下正常工作
