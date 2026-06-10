# 后端模块：搜索、语义索引与 RAG

## 文档状态

active

## 代码位置

- Router: `backend/app/routers/search.py`
- Embedding: `backend/app/services/embedding_service.py`
- Summary: `backend/app/services/content_summary_service.py`
- Database FTS: `backend/app/core/database.py`

## 功能

- 关键词搜索和 FTS。
- 语义搜索。
- 内容摘要和 RAG chunk 生成。
- 语义索引状态、重建和失败 embedding 重试。

## 不承担职责

- 不管理内容入库。
- 不直接执行平台抓取。
- 不替代 Agent 对话体验。

## 实现逻辑

内容入库后按配置生成摘要和语义 chunk，写入 `content_embeddings`。语义搜索通过 embedding 相似度返回匹配内容。FTS 使用 SQLite FTS5。

## 测试

- `backend/tests/test_embedding_service.py`
- `backend/tests/test_content_summary.py`
- `backend/tests/test_database_fts.py`
- `backend/tests/test_api/test_semantic_search.py`

## 与其他模块交互

- contents: 来源正文、媒体引用和摘要。
- config-system: AI 能力、模型和索引策略。
- agent: Agent 可使用搜索工具读取内容。

## 对应前端

- 收藏库语义搜索。
- Agent 工作台。
- 内容详情后处理状态。

## API 接口

- `GET /api/v1/search/semantic`
- `GET /api/v1/search/semantic/index-status`
- `POST /api/v1/search/semantic/reindex`
- `POST /api/v1/search/semantic/embeddings/{embedding_id}/retry`

## 配置与策略

- embedding 模型、摘要模型、语义索引开关和重建成本控制应来自系统设置。
- 自动索引和手动重建都应受用户级策略约束。

## 当前问题

语义搜索当前仍更像搜索模式，不是完整问答模式。用户级语义索引开关和成本控制仍需收敛。

## 尚未实现 / 计划扩展

RAG 问答入口应在 Agent 或独立问答界面中设计，不应混入收藏列表搜索模式。
