# 03 — 坏味道目录

## 严重性说明

- 🔴 **高**：数据完整性风险 / 静默失败 / 功能缺失
- 🟡 **中**：正确性问题 / 可靠性隐患 / 维护性陷阱
- 🟢 **低**：技术债 / 扩展性问题 / 代码质量

---

## 高危问题（🔴 H）

### H1：向量索引完全 fire-and-forget，无追踪无重试

**位置**：`tasks/parsing.py:_schedule_embedding_index()`

```python
asyncio.create_task(EmbeddingService.index_content(content_id))
# 无 add_done_callback，无状态标记
```

**问题**：Gemini API 不可用时，任务静默失败。`Content` 表无 `embedding_status` 字段，无法区分"未索引"与"索引中"。该内容永远不会出现在向量搜索结果中，用户无任何感知。

**根因**：把"非关键但重要"的副作用用 fire-and-forget 处理，没有补偿机制。

---

### H2：Discovery 内容永远不生成向量索引

**位置**：`tasks/discovery_sync.py`

**问题**：RSS / Telegram Channel 抓取的内容直接以 `status=PARSE_SUCCESS` 入库，绕过解析队列，不调用 `_schedule_embedding_index()`。这部分内容在向量搜索中完全不可见，只能走 FTS 全文搜索。

**影响**：如果 Discovery 是主要内容来源，向量搜索质量将严重低于预期。

---

### H3：QR 认证会话是进程局部状态，多 worker 部署必然出错

**位置**：`services/browser_auth_service.py`

```python
self.sessions: dict[str, Any] = {}  # 实例属性，进程局部
```

**问题**：Uvicorn `--workers 2+` 部署时，QR start 请求落在 Worker A，QR poll 请求可能落在 Worker B。Worker B 的 `sessions` 是空的，poll 必然失败。用户扫码后看到"未授权"错误。

**根因**：有状态的 HTTP 流程（QR 登录是两步式交互）没有持久化中间状态。

---

### H4：配置四头分裂（Split-Brain Config）

**位置**：`core/config.py`、`services/settings_service.py`、`services/content_summary_service.py`

**问题**：配置的 Source of Truth 分裂为四处：
1. `.env` 文件 → `Settings` 对象（启动时读取）
2. `Settings` 对象 → 被 `setattr` 动态修改（运行时）
3. `_SETTINGS_CACHE` → 模块级 dict，无 TTL，无跨进程同步
4. `system_settings` 表 → 实际持久化位置

更严重：`content_summary_service.py` 用 `os.environ.get("GEMINI_API_KEY")` 直接读环境变量，完全绕过上述所有层。

**后果**：通过 UI 修改的 Gemini API Key 对摘要服务不生效；多进程部署下修改配置只对当前进程生效。

---

## 中危问题（🟡 M）

### M1：向量搜索全表扫描，无 ANN 索引

**位置**：`services/embedding_service.py:_vector_rank_ids()`

```python
# 加载所有 ContentEmbedding 行到内存，在 Python 中做 numpy 点积
rows = await session.execute(select(ContentEmbedding).join(Content).where(...))
```

**问题**：10,000 内容 × 5 chunk = 50,000 行，每次搜索全部加载。随库增长，响应时间线性增长，最终导致超时或 OOM。SQLite 无向量索引能力，需引入 FAISS 或迁移到 pgvector。

---

### M2：自动审批逻辑重复实现

**位置**：`tasks/parsing.py:_check_auto_approval()` 和 `services/distribution/engine.py:auto_approve_if_eligible()`

**问题**：两处都实现了"查询规则 → 匹配 → 设置 AUTO_APPROVED → 入队分发"的完整逻辑。修改审批条件必须同时改两处。解析后立即执行一次，规则刷新时再执行一次，可能产生不一致结果（如规则在两次执行之间被修改）。

---

### M3：`content_summary_service` 硬编码模型名称

**位置**：`services/content_summary_service.py`

```python
response = client.models.generate_content(
    model="gemini-3.1-flash-lite-preview",  # 硬编码！
    ...
)
```

**问题**：用户在设置界面配置的 AI 模型只影响 `EmbeddingService`，不影响 `SummaryService`。两个 AI 调用使用不同模型，用户完全不知情。

---

### M4：`EventBus` 类属性 vs 实例属性混用

**位置**：`core/events.py`

```python
class EventBus:
    _subscribers: list[asyncio.Queue] = []  # 类属性
    _lock: asyncio.Lock = asyncio.Lock()    # 类属性

event_bus = EventBus()  # 对外暴露为实例
```

**问题**：所有实例共享同一个 `_subscribers` 列表。测试中创建第二个 `EventBus()` 实例时会共享订阅者，可能导致 ghost 事件或双重投递。`_last_seen_event_id` 在 `_poll_remote_events()` 中被无锁写入，与并发 `publish()` 存在竞争。

---

### M5：`SemanticChunk` / `ContentIntelligence` 重复定义

**位置**：`services/content_summary_service.py` 和 `services/embedding_service.py`

**问题**：两个服务各自定义了几乎相同的 Pydantic 模型作为 AI 输出的解析目标。`rich_payload["chunks"]` 字段是两者通信的隐式契约，无 schema 约束。若任意一方修改字段名，另一方静默解析失败。

---

### M6：`ContentParser` 神类（848 行）

**位置**：`tasks/parsing.py`

**职责过载**（单个类承担以下所有责任）：
- 队列编排 + 状态机管理
- 平台 Adapter 调用 + 指数退避重试
- 媒体归档：图片下载 / WebP 转换 / 视频下载 / URL 重写（>200 行）
- 摘要生成（调用 summary_service）
- 向量索引调度
- 自动审批判断
- 事件广播
- 死信队列管理

**影响**：任何链路改动都需要打开这个文件，心智负担极重，极难测试单个阶段。

---

### M7：`_check_auto_approval` 内联 import 掩盖循环依赖

**位置**：`tasks/parsing.py`，共 8 处函数体内 import

```python
async def _update_content(self, ...):
    from app.services.content_summary_service import generate_summary_for_content  # 函数体内！
    from app.core.events import event_bus  # 函数体内！
```

**问题**：这是用运行时 hack 绕过循环 import。静态分析工具和 IDE 看不到这些依赖，重构时容易漏改。根因是 `parsing.py` 承担了太多职责，导致被多个模块相互依赖。

---

### M8：`EmbeddingService` 每次调用 new 一个 Gemini Client

**位置**：`services/embedding_service.py:_embed_text()` 和 `_embed_multimodal()`

```python
def _call_gemini():
    client = genai.Client(api_key=api_key)  # 每次调用创建新 client
    return client.models.embed_content(...)
```

**问题**：N 个 chunk 的文章 = N+1 次 `genai.Client()` 实例化（1次全局摘要 + N次分块）。每次可能建立新的 HTTP 连接。每次调用还触发 3 次 settings DB 读（`_get_embedding_model`/`_get_embedding_api_key`/`_get_embedding_output_dimensionality`）。

---

### M9：`TelegramPushService._get_bot()` 无初始化锁

**位置**：`push/telegram.py`

```python
async def _get_bot(self):
    if self._bot is None:
        self._bot = Bot(token=...)  # 并发调用可能初始化两次
```

**问题**：多个 distribution worker 并发 push 时，首次都看到 `_bot is None`，可能创建多个 Bot 实例。GIL 防止内存损坏，但多余的连接建立是浪费，且最终只有一个实例被保留。

---

### M10：`PatrolService` 串行 LLM 调用导致评分积压

**位置**：`tasks/discovery_sync.py` → `patrol_service.score_pending()`

**问题**：串行逐条调用 LLM，N 条待评分内容 × 2s/条 = 2N 秒。60s 同步周期下，若每轮新增 >30 条，积压无限增长。

---

## 低危问题（🟢 L）

### L1：多个其他 God File

| 文件 | 行数 | 主要问题 |
|---|---|---|
| `adapters/zhihu.py` | 945 | Cookie 刷新 + ZSE 签名 + 多种内容类型混合 |
| `adapters/utils/content_agent.py` | 936 | LLM 提取编排 + 多平台特殊处理 |
| `routers/distribution_queue.py` | 801 | CRUD + 手动推送 API 混合 |
| `routers/bot_management.py` | 696 | Bot 生命周期 + 聊天管理混合 |
| `services/browser_auth_service.py` | 674 | QR 流程 + Cookie 持久化 + 多平台混合 |

---

### L2：`BrowserAuthService.sessions` 内存泄漏

**位置**：`services/browser_auth_service.py`

`self.sessions[platform]` 在 QR 开始时写入，无过期清理。用户发起 QR 流程后关闭浏览器，session entry 永远留在内存中。长期运行进程中缓慢积累。

---

### L3：`BackgroundTaskLeader` PID 文件在 Windows 上不完全原子

**位置**：`services/background_task_leader.py`

`os.open(O_CREAT|O_EXCL)` 在 POSIX 上是原子的，但在 Windows NTFS 受文件系统过滤驱动影响存在 TOCTOU 窗口。项目明确运行在 Windows 11 上（根据环境信息）。

---

### L4：Bot 子进程每条命令一次 HTTP 往返，无重试

**位置**：`bot/commands.py`

Backend 重启期间所有进行中命令报 `ConnectionRefused`。Bot handler 无重试逻辑，用户看到无响应。

---

### L5：`_DistributionQueueWorker` worker_count 不支持热更新

**位置**：`tasks/distribution_worker.py`

并发 worker 数量在 lifespan 启动时固定。需要重启整个 Backend 进程才能生效，无法在运行时调整。

---

### L6：Discovery 评分使用 LangChain，Summary 使用 Google GenAI SDK，两套 AI 接入方式并存

**位置**：`services/patrol_service.py`（LangChain）vs `services/content_summary_service.py`（google.genai SDK）

增加维护和配置复杂度。API Key 管理逻辑也因此分裂：LLMFactory 管 LangChain 模型的 key，content_summary 直接读 env/settings，EmbeddingService 读 settings。

---

### L7：`agent/service.py` 的工具路由基于正则关键词匹配

**位置**：`services/agent/service.py:_infer_tool_from_message()`

纯关键词正则匹配确定调用哪个工具，脆弱。歧义输入或组合意图无法处理。且 `_REGISTRY` 单例无锁懒初始化，并发首次调用存在理论竞争。
