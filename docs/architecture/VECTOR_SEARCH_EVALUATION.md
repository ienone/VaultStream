# 语义检索向量索引评估

更新日期：2026-05-14

## 当前实现

当前 `EmbeddingService.search_similar()` 使用 `content_embeddings` 普通表保存 JSON 向量，并通过多层收敛控制成本：

- 先按 `top_k` 计算候选上限，当前为 `max(50, top_k * 6)`。
- 向量行扫描受 `embedding_search_max_rows` 限制，默认最多读取 5000 行；候选按 `indexed_at` 降序收敛后再在应用层计算相似度。
- 结合 FTS 候选、向量候选与内容状态过滤后，在应用层计算 cosine 相似度。
- 日志记录 `candidate_limit`、`vector_candidates`、`fts_candidates`、`result_count`、`elapsed_ms`、`vector_scan_rows`、`vector_scan_limit`，用于判断是否需要切换专用向量索引。

这个方案的优点是部署简单、与现有 SQLite/Windows/单机自托管一致，不需要加载 SQLite 扩展或维护额外索引文件。缺点是高数据量下仍会受 Python 层向量计算和 JSON 反序列化影响。

## 选项评估

| 方案 | 结论 | 原因 |
| --- | --- | --- |
| 继续当前 SQLite 表 + 候选收敛 | 当前采用 | 最少部署复杂度；已具备候选限制和耗时日志；适合当前自托管规模。 |
| sqlite-vec | 后续优先试点 | 官方 README 标注它是 sqlite-vss 的 successor，纯 C、无依赖、支持 Python 安装和 `vec0` 虚拟表；但仍是 pre-v1，需接受破坏性变更风险。 |
| sqlite-vss | 暂不采用 | 官方 README 明确不再活跃开发，并转向 sqlite-vec；还依赖 Faiss，存在 UPDATE 不支持、部分索引训练/插入成本高等约束。 |
| 独立 Faiss 索引 | 暂不采用 | Faiss 适合大规模相似度搜索，也支持磁盘索引；但会引入 SQLite 外的索引生命周期、一致性与部署复杂度。当前项目的单机 SQLite 模型还不需要这一步。 |

参考来源：

- sqlite-vec: https://github.com/asg017/sqlite-vec
- sqlite-vss: https://github.com/asg017/sqlite-vss
- Faiss: https://faiss.ai/

## 决策

短期继续保留当前实现，不把 sqlite-vec/sqlite-vss 加入运行依赖。这样不会扩大 Docker、Windows 本地开发和 CI 的安装面。

中期以 sqlite-vec 作为唯一 SQLite 内嵌向量索引候选，不再投入 sqlite-vss。触发试点的条件：

- `content_embeddings` 超过 50,000 行；或
- `/api/v1/search/semantic` p95 超过 300ms；或
- 语义检索日志连续出现 `candidate_limit` 命中且结果相关性下降。

试点时新增 feature flag，例如 `VECTOR_INDEX_BACKEND=sqlite_vec`，保持当前 JSON 表作为回退来源，并提供 backfill 脚本把 `content_embeddings.embedding` 同步到 `vec0` 虚拟表。
