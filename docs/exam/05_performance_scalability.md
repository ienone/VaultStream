# 性能与数据层审计

## SQLite 当前状态

本次对 `backend/data/vaultstream.db` 做了基础检查：

- 文件存在，约 6.6MB。
- `PRAGMA integrity_check` 返回 `ok`。
- `PRAGMA foreign_key_check` 返回空。
- 16 张表，86 个索引。

这说明当前样本库结构没有明显损坏，问题更多在“能力承诺与索引/检索实现是否闭环”。

## FTS 缺失导致搜索退化

文档 `docs/DATABASE.md` 声明：

- `contents_fts` FTS5 表
- insert/update/delete triggers

但当前 DB 表清单没有 `contents_fts`。代码搜索也未发现创建 FTS 表或触发器的 migration。`backend/app/utils/text_search.py` 查询 FTS 异常后返回空列表，后续只能依赖 LIKE 或向量路径。

影响：

- 关键词搜索性能会随着内容量增长退化。
- 搜索质量不稳定，中文分词/字段权重无法发挥。
- 文档、接口和用户感知不一致。

建议：

1. 新增显式 migration 创建 `contents_fts` 和 triggers。
2. 启动时 health check 检测 FTS 是否存在。
3. 对已有内容提供 backfill 命令。
4. FTS 不可用时在日志和 API metadata 中暴露降级状态。

## 向量检索是 O(N) 路径

`backend/app/services/embedding_service.py` 中：

- embedding 存储在 `content_embeddings.embedding` JSON 字段。
- `_vector_rank_ids()` 查询候选 rows 后在 Python 中逐条转 numpy、点积、排序。
- 当前索引只覆盖 `content_id`、`chunk_index`、`indexed_at`、`model` 等普通字段，没有向量索引。

影响：

- 小库可用；内容和 chunk 数量上来后查询延迟线性增长。
- SQLite JSON 存向量不利于压缩、批量计算和 ANN。

建议：

- 短期：限制候选范围、缓存 query embedding、记录耗时和候选数量。
- 中期：使用 sqlite-vec/sqlite-vss，或独立向量索引。
- 长期：统一 text FTS + vector rerank pipeline，并把向量索引 backfill 纳入任务队列。

## Discovery/RAG 数据链路未闭环

Discovery sync 创建内容并运行 Patrol 评分，但未看到 embedding indexing。结果：

- Discovery 内容可能无法被 semantic search 命中。
- RAG 覆盖率取决于内容来源，而不是统一内容状态。

建议建立 post-ingest hook：

```text
Content created/updated
  -> normalize rich_payload
  -> summary/intelligence
  -> embedding index
  -> patrol score
  -> distribution queue
```

## 媒体代理性能

`/proxy/image` 当前会：

- 下载远程图片到 `resp.content`。
- 转码 WebP。
- 写入本地 storage。
- 返回完整 bytes。

风险：

- 没有看到响应体大小上限。
- 没有像素尺寸上限。
- 转码失败时仍缓存原图。
- 缓存只有目录命中逻辑，未看到全局配额/清理策略。

建议：

- 限制 Content-Length 和累计读取大小。
- 限制解码像素数，避免压缩炸弹。
- 增加 proxy cache 配额和 LRU/TTL 清理。
- 对失败/非图片响应不要缓存。

## 前端性能

### SSE 刷新

collection 页面与 provider 都可能响应 SSE 事件，建议统一刷新 owner，避免重复 invalidation。

### 图片库

`cached_network_image` 与 `extended_image` 同时使用是可接受的，但需要边界：

- 列表/卡片缩略图：`CachedNetworkImage`。
- 全屏 gallery/手势缩放：`ExtendedImage`。

如果边界不清，会导致缓存、占位、错误态、内存释放策略不一致。

### 字体

Google Fonts 运行时加载可能造成首屏抖动和离线不可用。建议打包字体资产，或禁用 runtime fetching。
