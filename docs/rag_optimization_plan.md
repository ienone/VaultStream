# VaultStream RAG 架构底层优化指导书

本文档聚焦于目前 VaultStream 后端在“检索增强生成（RAG）”链路的代码现状，梳理了目前潜藏的架构风险与性能瓶颈，并给出了精准到文件的源码修改实施方案。

---

## 优化方向一：修复“数据不同步”的时序 Bug（向 Agentic RAG 演进）

### 1. 痛点分析
当前 VaultStream 后端在成功解析一篇文章后，对于入库向量（Embedding）和 AI 智能总结的时序处理存在明显的竞态与遗漏缺陷：
在 `backend/app/tasks/parsing.py` 的解析流中：
1. 提前触发了异步生成向量：`_schedule_embedding_index`
2. 随后才执行：`AWait generate_summary_for_content` (调用多模态模型提取视觉+摘要)
**这导致：模型花大力气通过 Vision LLM 生成的优质摘要甚至视觉特征，大概率赶不上入库时间，导致生成的检索向量中完全丢失了高浓缩语义！**

### 2. 代码重构指引
*   **修改文件**：`backend/app/tasks/parsing.py` -> `_update_content` 函数
*   **动作**：
    将建立语义索引的代码下移，确保必须等待高质量摘要落地乃至事务提交后再触发向量运算。
    ```python
    # 修改前：
    self._schedule_embedding_index(content.id)
    if enable_auto_summary:
        await generate_summary_for_content(...)
    
    # 🌟 修改后：
    if enable_auto_summary:
        await generate_summary_for_content(...)
    # 确保拿到最终版的 summary, rich_payload 后再发给大模型做向量抽取
    self._schedule_embedding_index(content.id)
    ```

### 3. 高级扩展：让大模型为检索定制“提纯 Payload”
单纯将前 4000 个乱码字符作为向量入库是“古典主义”做法。
*   **修改文件**：`backend/app/services/content_summary_service.py` 
*   **动作**：将原来的 Prompt 升级，不仅让它只返回 120 字的展示级摘要，要求其返回包含 `{"rag_keywords": ["..."], "core_arguements": "..."}` 的结构化 JSON，存入 `content.rich_payload` 或 `context_data`。
*   **修改文件**：`backend/app/services/embedding_service.py` -> `_build_content_text`
*   **动作**：在拿原文组装字符串时，强行塞入上述 LLM 提纯后的 `rag_keywords`。将极大地拔高长文检索的准确度。

---

## 优化方向二：告别“手算”，矩阵提速近百倍

### 1. 痛点分析
当前 VaultStream 在计算搜索时，使用的是极度消耗系统性能的 Native Python 双层循环：
把整个 SQLite / Postgres 里的数组通过 ORM 拉进内存，进行 `sum(a[i] * b[i])`。当书签积累达数万条级别，高并发查询时必定引发 API 响应超时与 CPU 爆满。

### 2. 代码重构指引
*   **修改文件**：`backend/app/services/embedding_service.py` -> `_vector_rank_ids`
*   **动作**：引入 C 原生的 `NumPy`。因为数据在建立向量时已经经过 `$L2$` 标准化处理（`_normalize_vector`），余弦相似度完全等价于极速的“内积（Dot Product）”。
    ```python
    import numpy as np
    
    # 替换原本慢速的 for 循环计算过程
    async def _vector_rank_ids(self, ...):
        # ... fetch rows
        if not rows: return []
        
        q = np.array(query_vec, dtype=np.float32)
        # 将数组极速转为二维矩阵
        doc_ids = np.array([r[0] for r in rows])
        doc_matrix = np.array([self._coerce_vector(r[1]) for r in rows], dtype=np.float32)
        
        # 🌟 矩阵算子一步直出，无惧万级运算量
        scores = np.dot(doc_matrix, q)
        
        # 用内置 argsort 高效取 Top-K
        top_indices = np.argsort(scores)[::-1][:limit]
        return [(int(doc_ids[idx]), float(scores[idx])) for idx in top_indices]
    ```

---

## 优化方向三：封堵“模型更迭”带来的数据灾难污染

### 1. 痛点分析
模型之间的向量维度和空间定义是天生隔离的。
目前，如果用户在 Admin 后台从默认的 `text-embedding-3-small` (1536维) 切换到例如 BGE-M3 (1024维)：
`_vector_rank_ids` 的 SQL 查询并未隔离旧模型数据，并且 `_cosine_similarity` 里面有一行“工程妥协”代码：`length = min(len(a), len(b))`。
它会导致系统拿出 1024 维度的提问，硬生生切掉旧文档 1536 维度多出的尾巴，强行混合计算。得出完全错误的垃圾分数。

### 2. 代码重构指引
*   **修改文件**：`backend/app/services/embedding_service.py` -> `_vector_rank_ids`
*   **动作**：在 SQLAlchemy 的 Where 组装条件中，强势加入 `embedding_model` 匹配！
    ```python
    current_model = await self._get_embedding_model()
    # 只有使用当前激活模型构建的数据才有资格参与算排名！宁缺毋滥。
    filters.append(ContentEmbedding.embedding_model == current_model)
    ```
*   **配套动作**：建议在 `System` 路由中，暴露一个 API 接口：`POST /api/reindex_embeddings`，用于当用户主动更换向量服务方后，清空 `ContentEmbedding` 表并扔给 Task Queue 进行全站后台重刷。

---

## 远期架构演进路线（Roadmap）

### 最终形态：引入大引擎下推（DB Operator）
随着用户的私人收藏达到数十万量级，即使用 `Numpy` 也会造成庞大的网络 IO 开销。
*   **SQLite**：推荐挂载 `sqlite-vec` 或者 `vss` 的 `.so/.dll` 动态链接库。
*   **PostgreSQL**：为 `ContentEmbedding.embedding` 字段直连 `pgvector` 插件。
代码里直接提交带 `<=>` 符号的 SQL，剥离 Python 所有的计算逻辑包袱。

### 颠覆形态：“真·多模态原生” 向量引擎降维打击
当前通过 `content_summary_service` 翻译图片 -> 落文字 -> 用通用文本生成向量 的链路存在信息折损。
未来若切换至如 **Gemini Embedding 2** 级别的新生代引擎。无需事先解析内容，直接将 HTML Part + 图片二进制文件流 Part 打包提交至 API，返回一个极度高纯度的原生多模态联合坐标点存入 DB。届时“以图搜文”、“以文搜复杂版式文章”将顺手拈来。
