# 02 — 10 条数据流全链路追踪

## Chain 1：内容采集链路

**入口**：`POST /api/v1/contents/share`

```
HTTP POST /contents/share {url}
  └── ContentService.create_share(url, session)
        ├── normalize_url(url)                          [纯函数]
        ├── detect_platform(url)                        [纯函数]
        ├── SELECT Content WHERE canonical_url          [DB 读：去重]
        │     └── 若存在 → 返回现有记录（幂等）
        ├── INSERT Content (status=PENDING)             [DB 写]
        ├── INSERT ContentSource                        [DB 写]
        ├── session.commit()
        ├── task_queue.enqueue(content_id)              [DB 写：tasks 表]
        └── event_bus.publish("content_created")       [DB 写 + 内存广播]

后台 TaskWorker（lifespan 启动的 asyncio.Task）：
  └── task_queue.dequeue()
        ├── SELECT task WHERE status=PENDING            [DB 读]
        ├── UPDATE task SET status=RUNNING              [CAS 写，检查 rowcount]
        └── ContentParser.process_parse_task(task)     ← 848 行神类
              ├── UPDATE Content SET status=PROCESSING  [DB 写]
              ├── session.commit()
              ├── _execute_parse_with_retry(content)
              │     └── PlatformAdapter.parse(url)     [HTTP / Playwright I/O]
              │           最多重试 N 次
              ├── _update_content(content, parsed)
              │     ├── 复制 ParsedContent 字段到 ORM
              │     ├── _maybe_process_private_archive_media()
              │     │     ├── storage.put_bytes(img) × N  [文件 I/O]
              │     │     └── 内联修改 media_urls / cover_url / body [内存写]
              │     ├── generate_summary_for_content()  ← 内联 import（循环依赖掩盖）
              │     │     ├── Gemini SDK（asyncio.to_thread）[网络 I/O]
              │     │     ├── 写 content.summary          [内存 → DB]
              │     │     ├── 写 content.tags（合并）      [内存 → DB]
              │     │     └── 写 content.rich_payload.chunks [内存 → DB]
              │     ├── UPDATE Content.status=PARSE_SUCCESS [内存]
              │     └── session.commit()                 [DB 写]
              ├── _schedule_embedding_index(content_id)
              │     └── asyncio.create_task(            ← 🔥 完全 fire-and-forget，无回调
              │           EmbeddingService.index_content(id))
              │               ├── _upsert_embedding(-1)  [全局摘要向量]
              │               └── per chunk:
              │                     └── _upsert_embedding(idx) [分块向量]
              ├── _check_auto_approval(content)
              │     ├── 查询匹配规则                      [DB 读]
              │     └── 若匹配: UPDATE review_status=AUTO_APPROVED [DB 写]
              │           └── enqueue_content_background() [asyncio.create_task]
              └── task_queue.mark_complete(task_id)      [DB 写]
```

**状态突变点汇总**：
- DB 写：tasks(×2), contents(×3), content_sources(×1), system_events(×1), content_embeddings(1+N)
- 文件写：N 张图片
- 内存写：`_subscribers` 队列广播

**异步边界**：
- `generate_summary_for_content()` → `asyncio.to_thread`
- `_schedule_embedding_index()` → `asyncio.create_task`（detached，无 done_callback）
- PlatformAdapter 可能经 `browser_manager.submit_coro()` 跨线程

---

## Chain 2：分发推送链路

**入口**：内容审批（手动 / 自动）或规则刷新

```
手动审批路径：
POST /contents/{id}/review {action: APPROVED}
  └── ContentService.review_card(id, APPROVED)
        ├── UPDATE content.review_status=APPROVED       [DB 写]
        ├── session.commit()
        └── _enqueue_distribution(content_id)
              └── enqueue_content_background(id)        [asyncio.create_task]
                    └── enqueue_content(id, session)
                          ├── SELECT Content            [DB 读]
                          ├── SELECT DistributionRule WHERE enabled [DB 读]
                          ├── SELECT DistributionTarget             [DB 读]
                          ├── per (rule, target):
                          │     ├── should_distribute() [纯函数]
                          │     └── INSERT ContentQueueItem (ON CONFLICT DO NOTHING)
                          ├── session.commit()
                          └── event_bus.publish("queue_updated") [DB 写 + 广播]

DistributionQueueWorker（N 并发 workers，lifespan 启动）：
  └── _worker_loop()
        ├── _claim_items()
        │     ├── SELECT ContentQueueItem WHERE status=SCHEDULED [DB 读]
        │     └── UPDATE SET status=PROCESSING, locked_by=worker_id [CAS 写]
        └── _process_item(item)
              ├── SELECT BotChat                        [DB 读]
              ├── SELECT PushedRecord（去重检查）        [DB 读]
              ├── _build_content_payload()              [纯 + 文件 I/O]
              │     └── storage.get_bytes()（asyncio.to_thread）
              ├── PushService.push(payload, bot_chat)   [Telegram / Napcat API]
              │     └── 懒初始化 Bot 实例（无锁！）
              ├── INSERT PushedRecord                   [DB 写]
              ├── UPDATE ContentQueueItem=SUCCESS       [DB 写]
              ├── UPDATE BotChat.push_count += 1        [DB 写]
              └── event_bus.publish("item_pushed")      [DB 写 + 广播]
```

**竞争条件**：`_claim_items()` 的 SELECT + UPDATE 未包在 `BEGIN IMMEDIATE` 中，并发 worker 可能双重读取同一条目。

---

## Chain 3：发现（Discovery）同步链路

**入口**：`DiscoverySyncTask._sync_loop()`，每 60 秒触发一次

```
定时 60s：
  └── DiscoverySyncTask._sync_loop()
        └── per enabled DiscoverySource:
              └── _sync_single_source(source)
                    ├── scraper.fetch(source)           [HTTP I/O，RSS/Telegram]
                    │     返回 list[DiscoveryItem]
                    ├── per item:
                    │     ├── SELECT Content WHERE canonical_url [去重读]
                    │     ├── INSERT Content (            [DB 写]
                    │     │     status=PARSE_SUCCESS,    ← ⚠️ 跳过 PENDING 状态，不走解析队列
                    │     │     discovery_state=INGESTED
                    │     │   )
                    │     └── 下载媒体 → storage.put_bytes() [文件 I/O]
                    ├── UPDATE DiscoverySource.last_synced_at [DB 写]
                    ├── session.commit()
                    └── PatrolService().score_pending()  ← 每次 new 实例
                          ├── SELECT Content WHERE discovery_state=INGESTED [DB 读]
                          └── per content（串行！）:
                                ├── LLM.ainvoke(score_prompt) [网络 I/O，LangChain]
                                ├── UPDATE content.ai_score, .summary, .discovery_state [内存]
                                └── session.commit()     [DB 写]
```

**关键问题**：
- Discovery 内容以 `PARSE_SUCCESS` 直接入库，**不调用 `_schedule_embedding_index()`** → 永远不会出现在向量搜索结果中
- `PatrolService` 串行 LLM 调用，50 条内容 × 2s/条 = 100s，超过 60s 同步周期

---

## Chain 4：收藏夹同步链路

**入口**：`FavoritesSyncTask._sync_loop()` 定时 或 `POST /favorites/sync/trigger`

```
  └── FavoritesSyncTask.sync_all_platforms_once()
        ├── asyncio.Lock() acquire（进程内防并发）     ← ⚠️ 进程局部锁，多 worker 无效
        ├── per enabled platform (twitter / xhs / zhihu):
        │     ├── 读取 favorites_sync_cursor_{platform} [settings_service]
        │     ├── platform_fetcher.fetch_favorites(cursor) [HTTP I/O]
        │     ├── per item:
        │     │     ├── ContentService.create_share(url) [完整 Chain 1]
        │     │     └── asyncio.sleep(rate_limit_delay)
        │     └── set_setting_value("favorites_sync_cursor_{platform}", next_cursor)
        │           [DB 写 + _SETTINGS_CACHE 写]
        └── asyncio.Lock() release
```

---

## Chain 5：语义搜索链路

**入口**：`GET /api/v1/search?q=...`

```
  └── EmbeddingService.search(query, top_k, filters)
        └── _search_impl()
              ├── embed_query(query)
              │     └── _embed_text(query, RETRIEVAL_QUERY)
              │           ├── _get_embedding_model()       [settings_service × 1]
              │           ├── _get_embedding_api_key()     [settings_service × 1]
              │           ├── _get_embedding_output_dimensionality() [settings_service × 1]
              │           └── Gemini SDK（asyncio.to_thread）
              │                 └── 失败 fallback: _build_local_embedding()（TF-IDF 近似）
              ├── _vector_rank_ids(session, query_vec, filters)
              │     ├── _get_embedding_model()             [settings_service × 1]
              │     ├── _get_embedding_output_dimensionality() [settings_service × 1]
              │     ├── SELECT ContentEmbedding.* JOIN Content WHERE model LIKE pattern
              │     │     ⚠️ 全表扫描，加载所有行到内存
              │     ├── numpy dot product per row          [CPU，进程内]
              │     ├── 按分数排序
              │     └── 按 content_id 去重（保留最高分 chunk）
              ├── rank_ids_by_fts_or_like(session, query)
              │     ├── FTS5 MATCH 查询                   [SQLite FTS5]
              │     └── 失败 fallback: LIKE 模糊匹配
              ├── _rrf_merge(vector_ids, fts_ids, top_k)  [纯函数，RRF K=60]
              ├── SELECT Content WHERE id IN (merged_ids)  [DB 读]
              └── 构建 SemanticSearchHit(chunk_index, chunk_title) 列表
```

**扩展性危机**：10,000 条内容 × 5 chunk = 50,000 行，每次搜索全部加载进内存做 numpy 点积。无 ANN 索引，无 pgvector，无 FAISS。

---

## Chain 6：Bot 交互链路

**架构**：Bot 作为**独立子进程**运行，仅通过 HTTP 与 Backend 通信

```
Telegram 消息 → PTB 库（bot/main.py 子进程）
  └── 分发到对应 Handler：
        ├── /search, /get, /ai 等命令
        │     └── httpx.AsyncClient → Backend API     [HTTP 请求，每条命令一次]
        │           ├── GET /contents
        │           ├── POST /agent/run
        │           └── POST /distribution/queue/push-now
        └── ChatMemberHandler（新成员入群）
              └── POST /bot/chats                     [DB 写：INSERT BotChat]

Bot 心跳（每 30s）：
  └── PTB job_queue → POST /bot/heartbeat
        └── UPDATE BotRuntime.last_heartbeat_at       [DB 写]
```

**问题**：Backend 重启期间，所有进行中的 Bot 命令报 `ConnectionRefused`，Bot Handler 无重试逻辑。

---

## Chain 7：配置管理链路

**入口**：`PUT /api/v1/system/settings/{key}`，或内部 `set_setting_value()`

```
写入路径：
  set_setting_value(key, value)
    ├── INSERT OR REPLACE SystemSetting         [DB 写]
    ├── _SETTINGS_CACHE[key] = value            [内存写，进程局部]
    └── setattr(settings, key, value)           [修改全局 Pydantic 对象]
          ⚠️ 多 worker 进程：其他进程的 cache 和 settings 对象不更新

读取路径（热路径，有缓存）：
  get_setting_value(key)
    ├── _SETTINGS_CACHE.get(key)
    │     └── 命中：直接返回（无 DB 读）
    └── cache miss：SELECT SystemSetting WHERE key=key
          └── _SETTINGS_CACHE[key] = value → return

启动时（load_all_settings_to_memory）：
  └── SELECT SystemSetting all rows
        └── per row: _SETTINGS_CACHE[key] = value + setattr(settings, key, value)

特殊绕过（⚠️ 坏味道）：
  content_summary_service.py:
    gemini_key = os.environ.get("GEMINI_API_KEY")  ← 完全绕过 settings_service
    if not gemini_key:
        gemini_key = await get_setting_value("embedding_api_key")
```

---

## Chain 8：AI Agent 链路

**入口**：`POST /api/v1/agent/run` 或 Bot `/ai` 命令

```
POST /agent/run {message}
  └── AgentService.run_agent_message(message, session)
        ├── _infer_tool_from_message(message)    [纯函数，关键词正则匹配]
        ├── _get_or_create_registry(session)     [懒初始化，无锁！]
        │     └── AgentToolRegistry.__init__()   [注册所有工具]
        └── registry.invoke(tool_name, message, session)
              └── tool.run()（视工具而定）：
                    ├── search_tool  → EmbeddingService.search() [Chain 5]
                    ├── ingest_tool  → ContentService.create_share() [Chain 1]
                    └── summarize_tool → LLMFactory.get_text_llm().ainvoke()

WebSocket 流式输出（/agent/ws）：
  └── 每 256 字符一帧 + asyncio.sleep(0.02)     [模拟流式，非真正 streaming]
```

---

## Chain 9：浏览器认证链路

**入口**：`POST /api/v1/auth/{platform}/qr-start`

```
QR 登录流程（以小红书为例）：
POST /auth/xiaohongshu/qr-start
  └── BrowserAuthService._xiaohongshu_qr_flow()
        ├── GET XHS QR 接口                      [HTTP I/O]
        ├── 返回 QR 图片 URL + session token
        └── self.sessions["xiaohongshu"] = state [实例内存写]
              ⚠️ 进程局部 dict，多 worker 部署下 poll 请求可能落到不同进程

POST /auth/xiaohongshu/qr-poll
  └── _xiaohongshu_qr_poll()
        ├── GET XHS QR 状态接口（轮询）           [HTTP I/O]
        └── 成功后：_persist_cookie(platform, cookie)
              ├── set_setting_value("cookie_xiaohongshu", cookie) [DB + cache]
              └── setattr(settings, "cookie_xiaohongshu", cookie) [全局对象]

知乎 ZSE 刷新（特殊：使用 Playwright）：
  └── BrowserAuthService.refresh_zhihu_zse_cookie()
        ├── 检查 90s 冷却时间（实例内存 timestamp）
        ├── async with _zhihu_refresh_lock:       [asyncio.Lock，防并发]
        │     └── browser_manager.submit_coro(    [跨线程 Future]
        │           zhihu_adapter.refresh_zse_cookie()
        │         )                               [Playwright WebKit 操作]
        └── _persist_cookie("zhihu", new_cookie)
```

---

## Chain 10：SSE 事件链路

**入口**：`GET /api/v1/events`（SSE 长连接）

```
SSE 消费者：
GET /events (Last-Event-ID header)
  └── event_stream()
        ├── event_bus.replay_events_since(last_id) [SELECT system_events DB 读]
        │     └── yield 历史事件
        └── async with event_bus.subscribe() as queue:
              └── 无限循环：
                    ├── await queue.get() timeout=300s
                    │     └── 超时: yield "ping" 事件（保活）
                    └── yield event

事件生产者（任意服务）：
  event_bus.publish(event_type, payload, session)
    ├── INSERT SystemEvent                        [DB 写]
    ├── session.flush()
    └── _broadcast_to_local_subscribers(event)
          ├── async with EventBus._lock:          [类级锁]
          └── per queue in EventBus._subscribers:
                queue.put_nowait(event)           [内存写]
                ⚠️ 若消费者队列满，put_nowait 抛出 QueueFull

多进程远端轮询（EventBus._poll_remote_events）：
  └── 每 0.5s：
        ├── SELECT SystemEvent WHERE id > _last_seen_event_id [DB 读]
        ├── _last_seen_event_id = max_id          [类属性写，⚠️ 无锁！]
        └── _broadcast_to_local_subscribers()
```

---

## 异步边界汇总

| 边界 | 位置 | 类型 | 风险 |
|---|---|---|---|
| 解析任务分发 | `main.py` lifespan → worker | `asyncio.create_task` | 异常仅记录日志 |
| 向量索引调度 | `tasks/parsing.py._schedule_embedding_index` | `asyncio.create_task` | **完全 detached，无 done_callback，无重试** |
| 分发入队 | `content_service.py._enqueue_distribution` | `asyncio.create_task` | 异常被 bare except 吞噬 |
| Gemini 调用 | `embedding_service.py._embed_text` | `asyncio.to_thread` | 有 fallback |
| Gemini 摘要 | `content_summary_service.py` | `asyncio.to_thread` | 有 fallback，但调用方不检查结果 |
| Playwright | `browser_auth_service.py` | `asyncio.wrap_future`（跨线程） | 通过 Future 传播异常 |
| LangChain LLM | `patrol_service.py` | `await llm.ainvoke()` | per-item try/except |
| 存储 I/O | `adapters/storage/manager.py` | `asyncio.to_thread` | 向上抛异常 |
| Bot 子进程 | `telegram_bot_service.py` | `subprocess.Popen` | 同步阻塞检查 |
