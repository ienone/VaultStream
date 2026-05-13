# 04 — 架构图

## 图 1：当前认知模型（Current State Model）

梳理当前系统的调用链路与状态流转现状，重点标注问题点。

```mermaid
graph TD
    subgraph ENTRY["入口层"]
        API["FastAPI Routers\n/contents /search /discovery\n/distribution /agent /auth /events"]
        BOT["Telegram Bot 子进程\nbot/main.py\n每条命令 = 一次 HTTP 往返"]
        SCHEDULER["定时任务\n60s Discovery Sync\n收藏夹 Sync\n维护清理"]
    end

    subgraph CONFIG["配置层 ⚠️ 四头分裂"]
        ENV[".env 文件\n启动时读取"]
        SETTINGS_OBJ["Settings 单例\nPydantic BaseSettings\n⚠️ 运行时被 setattr 修改"]
        SETTINGS_CACHE["_SETTINGS_CACHE\nmodule-level dict\n⚠️ 无TTL / 无跨进程同步"]
        DB_KV["system_settings 表\nSQLite KV\n实际持久化位置"]
        OS_ENV["os.environ.get()\n⚠️ content_summary_service\n直接绕过所有层读取"]
        ENV --> SETTINGS_OBJ
        DB_KV <-->|"load_all / set"| SETTINGS_OBJ
        DB_KV <-->|"get_setting_value"| SETTINGS_CACHE
        OS_ENV -.->|"只在摘要服务生效\n其他服务不知道"| SETTINGS_CACHE
    end

    subgraph PARSE_PIPELINE["解析流水线 ⚠️ ContentParser 神类 848行"]
        TQ["TaskQueue 单例\nSQLite tasks 表"]
        PARSER["ContentParser\ntasks/parsing.py\n队列编排 + 重试\n媒体归档 >200行\n摘要调用\nEmbedding 调度\n自动审批\n事件广播\n死信队列\n⚠️ 8处 inline import"]
        TQ -->|dequeue + CAS lock| PARSER
        ADAPTER["PlatformAdapters\nbilibili/zhihu/weibo/xhs\ntwitter/rss/telegram/universal"]
        PARSER -->|HTTP / Playwright| ADAPTER
    end

    subgraph AI_LAYER["AI 层 ⚠️ 模型定义重复 / Key 读取路径不同"]
        SUMMARY["content_summary_service\n⚠️ 硬编码 gemini-3.1-flash-lite-preview\n⚠️ os.environ 直读\n定义 SemanticChunk（重复定义1）\n写 rich_payload.chunks"]
        EMBED["EmbeddingService\n⚠️ 每 chunk new genai.Client()\n⚠️ 每 chunk 3次 settings 读\n定义 SemanticChunk（重复定义2）\n全表扫描 O(N)"]
        GEMINI_A["Gemini SDK\n(摘要)"]
        GEMINI_B["Gemini SDK\n(向量化)"]
        PATROL["PatrolService\n⚠️ 串行 LLM 调用\n⚠️ 每轮 new 实例"]
        LANGCHAIN["LangChain LLM\n(Discovery 评分)"]
        SUMMARY -->|asyncio.to_thread| GEMINI_A
        EMBED -->|asyncio.to_thread| GEMINI_B
        PATROL -->|await ainvoke| LANGCHAIN
        SUMMARY -.->|"rich_payload['chunks']\n隐式契约，无 schema 约束"| EMBED
    end

    subgraph DISTRIBUTION["分发层 ⚠️ 自动审批逻辑重复"]
        ENGINE["DistributionEngine\nauto_approve_if_eligible()\n⚠️ 重复实现 #1"]
        PARSER_AUTO["ContentParser._check_auto_approval()\n⚠️ 重复实现 #2"]
        DIST_WORKER["DistributionQueueWorker\nN 并发 workers\n⚠️ _get_bot() 无初始化锁"]
        QUEUE_ITEMS["ContentQueueItem\nSQLite 分发队列\n⚠️ SELECT+UPDATE 非原子"]
        PUSH["PushService\nTelegram / Napcat\n懒初始化 Bot 实例"]
        ENGINE -->|INSERT| QUEUE_ITEMS
        PARSER_AUTO -->|INSERT| QUEUE_ITEMS
        DIST_WORKER -->|CAS claim| QUEUE_ITEMS
        DIST_WORKER -->|HTTP API| PUSH
    end

    subgraph DISCOVERY["Discovery 层 ⚠️ 不触发向量索引"]
        DISC_SYNC["DiscoverySyncTask\n60s 周期"]
        DISC_DB["DiscoverySource 表\nRSS / Telegram Channel"]
        DISC_CONTENT["Content 以 PARSE_SUCCESS 直接入库\n⚠️ 跳过解析队列\n⚠️ 永远不调用 _schedule_embedding_index"]
        DISC_SYNC -->|fetch| DISC_DB
        DISC_SYNC -->|INSERT| DISC_CONTENT
        DISC_CONTENT --> PATROL
    end

    subgraph EVENTS["事件层 ⚠️ 类属性 vs 实例属性"]
        EB["EventBus 实例\ncore/events.py\n⚠️ _subscribers 是类属性\n⚠️ _last_seen_event_id 无锁写入"]
        SSE["SSE 消费者\nGET /events"]
        EB --> SSE
    end

    subgraph AUTH["认证层 ⚠️ 进程局部状态"]
        QR["BrowserAuthService\n⚠️ self.sessions 进程局部 dict\n多 worker 部署必然出错\n⚠️ sessions 从不清理 → 内存泄漏"]
        PLAYWRIGHT["browser_manager\nPlaywright 独立线程"]
        QR --> PLAYWRIGHT
    end

    API --> PARSE_PIPELINE
    API --> AI_LAYER
    API --> DISTRIBUTION
    API --> AUTH
    BOT -->|HTTP 往返| API
    SCHEDULER --> DISCOVERY
    SCHEDULER --> PARSE_PIPELINE
    PARSER -->|asyncio.create_task\n🔥 fire-and-forget\n⚠️ 无重试无状态追踪| EMBED
    PARSER --> SUMMARY
    PARSER --> PARSER_AUTO
    PARSER --> EB
    CONFIG --> AI_LAYER
    CONFIG --> DISTRIBUTION
```

---

## 图 2：推荐状态模型（Refactored State Model）

基于高内聚低耦合原则，建议的最佳状态主体划分。

```mermaid
graph TD
    subgraph CONFIG2["配置层（统一）"]
        DB_KV2["system_settings 表\n唯一可写 Source of Truth"]
        CFG_SVC["ConfigService\n统一接口：get / set / watch\nTTL 内存缓存（5分钟）\n返回类型化 Config 对象\n无 setattr 修改全局对象"]
        AI_CFG["AIConfig\n(dataclass)\napi_key, model, dim\n每次 index_content 解析一次"]
        GC_POOL["GeminiClientPool\n单例，懒初始化\nAPI Key 变更时重建\n摘要 + 向量 共用"]
        DB_KV2 <--> CFG_SVC
        CFG_SVC --> AI_CFG
        CFG_SVC --> GC_POOL
    end

    subgraph SHARED_MODELS["共享数据契约（新增文件）"]
        RAG_SCHEMA["app/schemas/rag.py\nSemanticChunk (Pydantic)\nContentIntelligence (Pydantic)\nRagChunksPayload (Pydantic)\n单一定义，两服务 import 同一份"]
    end

    subgraph PARSE_PIPELINE2["解析流水线（职责分离）"]
        TASK_WORKER["TaskWorker\ntasks/runner.py\n只管：队列编排 + 重试 + 超时"]
        PLATFORM_ADAPTER["AdapterFactory\n平台解析\n返回 RawContent"]
        MEDIA_PROCESSOR["ArchiveMediaProcessor\n新拆出的独立类\n媒体下载 / 转码 / URL重写\n返回 ProcessedContent"]
        DIST_DECIDER["DistributionDecider\n合并两处重复的 auto-approval\n单一入口"]
        TASK_WORKER -->|"1. parse"| PLATFORM_ADAPTER
        PLATFORM_ADAPTER -->|RawContent| MEDIA_PROCESSOR
        MEDIA_PROCESSOR -->|ProcessedContent| TASK_WORKER
        TASK_WORKER -->|"4. check approval"| DIST_DECIDER
    end

    subgraph AI_PIPELINE2["AI 流水线（职责清晰，顺序约定）"]
        SUM_SVC2["SummaryService\n职责：调用 AI 生成 summary + tags + chunks\n写 content.rich_payload\nawait 完成后才触发下一步\n使用 ConfigService 读模型配置"]
        EMB_SVC2["EmbeddingService\n职责：读 rich_payload.chunks → 生成向量\n批量读取配置一次（非每 chunk）\n通过 GeminiClientPool 复用连接\n维护 embedding_status 字段"]
        EMB_INDEX["Content.embedding_status\n新字段：pending / indexed / failed\n可重试失败条目"]
        SUM_SVC2 -->|await 完成后\nasyncio.create_task| EMB_SVC2
        EMB_SVC2 --> EMB_INDEX
        RAG_SCHEMA -->|import| SUM_SVC2
        RAG_SCHEMA -->|import| EMB_SVC2
        GC_POOL -->|复用 client| SUM_SVC2
        GC_POOL -->|复用 client| EMB_SVC2
    end

    subgraph DISCOVERY2["Discovery 层（修正）"]
        DISC_SYNC2["DiscoverySyncTask\n修正：内容入库后\n显式调用 _schedule_embedding_index()"]
        PATROL2["PatrolService\n改为并发 LLM 调用\nasyncio.gather() 批量评分"]
        DISC_SYNC2 --> PATROL2
        DISC_SYNC2 -->|触发| EMB_SVC2
    end

    subgraph EVENTS2["事件层（修正）"]
        EB2["EventBus\n实例属性（非 classvar）\n_subscribers: list[asyncio.Queue]\n_last_seen_event_id: 实例属性 + 锁保护"]
    end

    subgraph AUTH2["认证层（修正）"]
        QR2["BrowserAuthService\nQR 会话状态持久化到 DB 或 Redis\n（不再是进程局部 dict）\nTTL 清理过期会话"]
    end

    CFG_SVC --> SUM_SVC2
    CFG_SVC --> EMB_SVC2
    TASK_WORKER -->|"2. await summary"| SUM_SVC2
```

---

## 图 3：目标架构组织图（Target Architecture）

采用建议后，新的状态流转全局视角。

```mermaid
flowchart TD
    subgraph INPUT["输入层"]
        URL_API["POST /contents/share"]
        BOT_CMD["Bot 命令 /save"]
        FAV_SYNC["收藏夹定时同步"]
        RSS_SYNC["RSS/Telegram 定时同步"]
    end

    subgraph QUEUE_LAYER["队列层"]
        TQ3["TaskQueue (SQLite tasks)\n原子 CAS dequeue"]
        TASK_WORKER3["TaskWorker\n只管编排 + 重试 + 超时\n不含业务逻辑"]
    end

    subgraph PARSE_LAYER["解析层（拆分后）"]
        ADAPTER3["AdapterFactory\n返回 RawContent dataclass"]
        ARCHIVE3["ArchiveMediaProcessor\n媒体归档 + URL重写\n返回 ProcessedContent"]
    end

    subgraph AI_LAYER3["AI 流水线（有序 + 有状态追踪）"]
        SUM3["SummaryService\nawait（阻塞直到完成）\n写 summary / tags / rich_payload.chunks"]
        EMB3["EmbeddingService\nasyncio.create_task（可追踪）\n读 chunks → 生成向量\n更新 embedding_status"]
        SUM3 -->|摘要完成后\nthen 触发| EMB3
    end

    subgraph DISTRIBUTION3["分发层"]
        DECIDER3["DistributionDecider\n单一 auto-approval 入口"]
        DIST_QUEUE3["ContentQueueItem\n(BEGIN IMMEDIATE 保护 claim)"]
        DIST_WORKER3["DistributionQueueWorker\nN workers，可热更新"]
        PUSH3["PushService\nTelegram / Napcat\nBot 单例带初始化锁"]
        DECIDER3 -->|INSERT| DIST_QUEUE3
        DIST_WORKER3 -->|原子 claim| DIST_QUEUE3
        DIST_WORKER3 -->|send| PUSH3
    end

    subgraph SEARCH_LAYER["检索层"]
        SEARCH3["EmbeddingService.search()\n混合检索：向量 + FTS5\nRRF 融合\n返回 SemanticSearchHit(chunk_index, chunk_title)"]
        note_faiss["TODO: FAISS / pgvector\n替换全表扫描"]
        SEARCH3 -.-> note_faiss
    end

    subgraph DISCOVERY_LAYER["Discovery 层（修正）"]
        DISC3["DiscoverySyncTask\n内容入库后显式触发 embedding"]
        PATROL3["PatrolService\nasyncio.gather() 并发评分"]
        DISC3 -->|"INSERT Content(PARSE_SUCCESS)\n+ 触发 embedding"| EMB3
        DISC3 --> PATROL3
    end

    subgraph CONFIG_LAYER["配置层（统一）"]
        CFG3["ConfigService\nTTL Cache + DB\n返回 AIConfig 对象\n无全局对象 mutation"]
        POOL3["GeminiClientPool\n单例，按 key+model 缓存"]
        CFG3 --> POOL3
    end

    subgraph EVENT_LAYER["事件层"]
        EB3["EventBus\n实例属性\n_subscribers 带容量保护\nput_nowait 异常有处理"]
        SSE3["SSE 消费者\nGET /events"]
        EB3 --> SSE3
    end

    subgraph AUTH_LAYER["认证层"]
        QR3["BrowserAuthService\nQR 状态 → DB 持久化\nTTL 自动过期"]
        PW3["browser_manager\nPlaywright 独立线程"]
        QR3 --> PW3
    end

    URL_API --> TQ3
    BOT_CMD -->|HTTP| URL_API
    FAV_SYNC --> URL_API
    RSS_SYNC --> DISC3

    TQ3 -->|原子 dequeue| TASK_WORKER3
    TASK_WORKER3 -->|1. parse| ADAPTER3
    ADAPTER3 -->|RawContent| ARCHIVE3
    ARCHIVE3 -->|ProcessedContent\n写入 DB + commit| TASK_WORKER3
    TASK_WORKER3 -->|2. await summary| SUM3
    TASK_WORKER3 -->|3. check approval| DECIDER3

    SUM3 --> EMB3
    CFG3 --> SUM3
    CFG3 --> EMB3
    POOL3 -->|复用 client| SUM3
    POOL3 -->|复用 client| EMB3

    TASK_WORKER3 -->|publish| EB3
    DIST_WORKER3 -->|publish| EB3

    SEARCH3 -.->|读| EMB3

    style SUM3 fill:#d4edda,stroke:#28a745,color:#000
    style EMB3 fill:#d4edda,stroke:#28a745,color:#000
    style CFG3 fill:#cce5ff,stroke:#004085,color:#000
    style POOL3 fill:#cce5ff,stroke:#004085,color:#000
    style ARCHIVE3 fill:#fff3cd,stroke:#856404,color:#000
    style DECIDER3 fill:#fff3cd,stroke:#856404,color:#000
    style TASK_WORKER3 fill:#f8d7da,stroke:#721c24,color:#000
    style DISC3 fill:#f8d7da,stroke:#721c24,color:#000
```

**图例**：
- 🟢 绿色：AI 服务（重构后职责清晰）
- 🔵 蓝色：配置层（统一后的单一来源）
- 🟡 黄色：待分离的子模块
- 🔴 红色：当前有问题的神类/链路（重构优先）
