# 架构审计

## 总体判断

当前后端大体遵循 `routers -> services -> repositories/adapters/tasks` 的分层，前端按 `features/` 与 `core/` 拆分，方向是正确的。但多个新增能力直接穿过既有边界：RAG/summary 直接读取环境变量并绑定 Gemini；Discovery 入库后没有统一进入 embedding/分发流水线；Agent 是工具注册 + 规则推断，而不是文档中暗示的对话式 Agent。

## 后端分层

### 已成立的边界

- `backend/app/routers/` 多数路由负责参数校验和调用 service，例如 `agent.py` 的 tool invoke/run API。
- `backend/app/services/distribution/decision.py` 已把分发规则判断独立为 `check_match_conditions` 与 `should_distribute`。
- `backend/app/tasks/` 承担解析、分发 worker、Discovery 同步等异步任务。

### 主要问题

1. 分发逻辑仍有多入口  
   `backend/app/tasks/parsing.py` 内部 `_check_auto_approval` 直接 import `check_match_conditions` 和 `enqueue_content`，`backend/app/services/distribution/engine.py` 又保留 `auto_approve_if_eligible`、`refresh_queue_by_rules`，`scheduler.py` 也有队列创建逻辑。后续改规则语义时容易出现“解析后自动审批”和“回填刷新”行为不一致。

2. Summary/RAG 绕过统一配置层  
   `backend/app/services/content_summary_service.py` 直接读取 `GEMINI_API_KEY` 和 DB setting `embedding_api_key`，并硬编码 `google.genai`、`gemini-3.1-flash-lite-preview`。这与项目已有的 provider/LLM 配置趋势不一致，也导致 `backend/tests/test_content_summary.py` 还在导入旧函数 `generate_summary_llm`。

3. Discovery 入库链路未接入 embedding  
   `backend/app/tasks/discovery_sync.py` 会创建 `Content` 并调用 `PatrolService().score_pending(db)`，但未看到 `EmbeddingService.index_content()` 或队列调度。结果是 Discovery 内容可能在列表/评分中可见，却缺席语义检索。

4. FTS 是架构文档承诺，但实现缺口明显  
   `docs/DATABASE.md` 声明 `contents_fts` 和触发器；当前 `backend/data/vaultstream.db` 没有该表，代码中也未找到创建表/触发器逻辑。`backend/app/utils/text_search.py` 查询失败后静默返回空，掩盖了该架构缺口。

5. Agent 当前是规则推断器，不是完整 Agent  
   `backend/app/services/agent/service.py:22-83` 用关键词和正则推断 tool；`backend/app/routers/agent.py:99-189` 支持 websocket streaming，但没有会话记忆、计划、模型调用或安全审批层。文档/路线图中如果称为 Agent，需要明确当前阶段是 “Tool facade / command router”。

## 前端架构

### 已成立的边界

- `frontend/lib/core/network/api_client.dart` 集中配置 Dio 和 API token。
- `frontend/lib/core/utils/safe_url_launcher.dart` 已存在安全 URL 打开 helper。
- `frontend/lib/features/collection/`、`discovery/`、`bot/`、`agent/` 等按业务拆分。

### 主要问题

1. 安全 helper 未统一落地  
   多个页面直接调用 `launchUrl(Uri.parse(...), externalApplication)`，包括内容详情、作者链接、用户 profile、知乎答案等。既然已有 `safe_url_launcher.dart`，应收敛到同一出口。

2. SSE 刷新职责重复  
   `frontend/lib/features/collection/collection_page.dart` 在 build 中 `ref.listen(sseEventStreamProvider)` 并 invalidates `collectionProvider`；同时 collection provider 自身也处理 SSE。需要确定一个 owner，否则容易重复刷新和难以复现的 UI 抖动。

3. Generated source 不在源码树  
   `frontend/lib` 中有 `part '*.g.dart'`/`*.freezed.dart`，但未找到对应生成文件。CI workflow 会跑 build_runner，但本地 analyze/test 前如果没有 codegen 就不可验证。

## 文档漂移

| 文档 | 当前漂移 |
| --- | --- |
| `docs/API.md` | 缺少 `/agent/tools`、`/agent/run`、`/agent/ws`、`/favorites-sync/*`、大量 discovery endpoint；distribution queue 文档未覆盖 `repush-now` |
| `docs/DATABASE.md` | 声明 FTS5，但当前 DB 无 `contents_fts`；迁移描述与实际 `Base.metadata.create_all` + init-time 兼容逻辑不一致 |
| `docs/architecture/BACKEND.md` | 提到旧 `storage.py`、`crawler.py` 等路径；CORS 示例和实际配置化逻辑不一致 |
| `docs/architecture/ROADMAP_V2.md` | RAG、Agent、Favorites sync 部分已有实现但状态未回填，容易误导后续规划 |

## 建议的目标架构收敛

1. 建立统一 ingest pipeline：解析、Discovery、收藏同步都进入同一套 post-ingest hook，统一触发 summary、embedding、patrol、distribution。
2. 建立唯一分发决策入口：路由、解析任务、回填任务都通过同一 service。
3. 建立 provider 配置中心：summary、embedding、patrol、agent 全部使用同一 LLM/provider 配置模型。
4. 建立 DB migration 入口：FTS、索引、兼容字段迁移全部显式化，避免文档和运行库继续分叉。
5. 给 Agent 降级命名或补齐能力：当前应文档化为 tool router；若继续称 Agent，需要补齐模型调用、session、审计和审批。

