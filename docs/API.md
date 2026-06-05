# VaultStream API 文档

> 版本: v0.1.0  
> 更新: 2026-05-18
> 本文档按当前代码实现更新（OpenAPI endpoint inventory + health diagnostics + ContentQueueItem + /distribution-queue/* + Agent/semantic search）

---

## 鉴权

所有 `/api/v1/*` 请求支持以下任一方式携带 Token：

- `X-API-Token: <token>`
- `Authorization: Bearer <token>`

未配置 `API_TOKEN` 时可跳过鉴权（仅建议本地开发）。

WebSocket 接口同样只接受请求头中的 `X-API-Token` 或 `Authorization: Bearer <token>`；不要把 token 放入 URL query。

---

## OpenAPI 端点清单

该清单由当前 FastAPI 应用的 OpenAPI schema 生成：

```powershell
.venv\Scripts\python.exe scripts\export_openapi_endpoints.py
```

| Methods | Path |
| :--- | :--- |
| `GET` | `/api` |
| `GET` | `/api/v1/actions` |
| `GET, POST` | `/api/v1/actions/{action_name}` |
| `GET` | `/api/v1/agent/confirmations/{confirmation_id}` |
| `POST` | `/api/v1/agent/confirmations/{confirmation_id}/decide` |
| `POST` | `/api/v1/agent/run` |
| `POST` | `/api/v1/agent/runs/{run_id}/stop` |
| `GET, POST` | `/api/v1/agent/sessions` |
| `DELETE, PATCH` | `/api/v1/agent/sessions/{session_id}` |
| `POST` | `/api/v1/agent/sessions/{session_id}/clear` |
| `GET` | `/api/v1/agent/sessions/{session_id}/messages` |
| `POST` | `/api/v1/agent/sessions/{session_id}/redo` |
| `GET` | `/api/v1/agent/sse` |
| `GET` | `/api/v1/agent/tools` |
| `POST` | `/api/v1/agent/tools/{tool_name}/invoke` |
| `GET, POST` | `/api/v1/bot-config` |
| `POST` | `/api/v1/bot-config/service/telegram/restart` |
| `POST` | `/api/v1/bot-config/service/telegram/start` |
| `POST` | `/api/v1/bot-config/service/telegram/stop` |
| `DELETE, PATCH` | `/api/v1/bot-config/{config_id}` |
| `POST` | `/api/v1/bot-config/{config_id}/activate` |
| `GET` | `/api/v1/bot-config/{config_id}/qr-code` |
| `POST` | `/api/v1/bot-config/{config_id}/sync-chats` |
| `GET, POST` | `/api/v1/bot/chats` |
| `POST` | `/api/v1/bot/chats/sync` |
| `DELETE, GET, PATCH` | `/api/v1/bot/chats/{bot_chat_id}` |
| `GET, PUT` | `/api/v1/bot/chats/{bot_chat_id}/rules` |
| `POST` | `/api/v1/bot/chats/{bot_chat_id}/toggle` |
| `PUT` | `/api/v1/bot/chats:upsert` |
| `POST` | `/api/v1/bot/heartbeat` |
| `GET` | `/api/v1/bot/runtime` |
| `GET` | `/api/v1/bot/status` |
| `POST` | `/api/v1/browser-auth/session/{platform}` |
| `GET` | `/api/v1/browser-auth/session/{session_id}/qrcode` |
| `GET` | `/api/v1/browser-auth/session/{session_id}/status` |
| `POST` | `/api/v1/browser-auth/zhihu/refresh-zse` |
| `DELETE` | `/api/v1/browser-auth/{platform}` |
| `POST` | `/api/v1/browser-auth/{platform}/check` |
| `POST` | `/api/v1/browser-auth/{platform}/logout` |
| `GET` | `/api/v1/cards` |
| `POST` | `/api/v1/cards/batch-review` |
| `GET` | `/api/v1/cards/{card_id}` |
| `POST` | `/api/v1/cards/{card_id}/review` |
| `GET` | `/api/v1/contents` |
| `DELETE, GET, PATCH` | `/api/v1/contents/{content_id}` |
| `POST` | `/api/v1/contents/{content_id}/generate-summary` |
| `POST` | `/api/v1/contents/{content_id}/re-parse` |
| `POST` | `/api/v1/contents/{content_id}/retry` |
| `GET` | `/api/v1/background-tasks/diagnostics` |
| `GET` | `/api/v1/background-tasks/metrics` |
| `GET` | `/api/v1/dashboard/queue` |
| `GET` | `/api/v1/dashboard/stats` |
| `GET` | `/api/v1/discovery/items` |
| `POST` | `/api/v1/discovery/items/bulk-action` |
| `GET, PATCH` | `/api/v1/discovery/items/{item_id}` |
| `GET, PATCH` | `/api/v1/discovery/settings` |
| `GET, POST` | `/api/v1/discovery/sources` |
| `DELETE, GET, PUT` | `/api/v1/discovery/sources/{source_id}` |
| `POST` | `/api/v1/discovery/sources/{source_id}/sync` |
| `POST` | `/api/v1/discovery/sources/{source_id}/test` |
| `GET` | `/api/v1/discovery/stats` |
| `POST` | `/api/v1/distribution-queue/batch-retry` |
| `POST` | `/api/v1/distribution-queue/content/batch-push-now` |
| `POST` | `/api/v1/distribution-queue/content/batch-repush-now` |
| `POST` | `/api/v1/distribution-queue/content/batch-reschedule` |
| `POST` | `/api/v1/distribution-queue/content/{content_id}/push-now` |
| `POST` | `/api/v1/distribution-queue/content/{content_id}/reorder` |
| `POST` | `/api/v1/distribution-queue/content/{content_id}/repush-now` |
| `POST` | `/api/v1/distribution-queue/content/{content_id}/schedule` |
| `POST` | `/api/v1/distribution-queue/content/{content_id}/status` |
| `POST` | `/api/v1/distribution-queue/enqueue/{content_id}` |
| `GET` | `/api/v1/distribution-queue/items` |
| `GET` | `/api/v1/distribution-queue/items/{item_id}` |
| `POST` | `/api/v1/distribution-queue/items/{item_id}/cancel` |
| `POST` | `/api/v1/distribution-queue/items/{item_id}/push-now` |
| `POST` | `/api/v1/distribution-queue/items/{item_id}/retry` |
| `GET` | `/api/v1/distribution-queue/stats` |
| `GET, POST` | `/api/v1/distribution-rules` |
| `GET` | `/api/v1/distribution-rules/preview/stats` |
| `DELETE, GET, PATCH` | `/api/v1/distribution-rules/{rule_id}` |
| `GET` | `/api/v1/distribution-rules/{rule_id}/preview` |
| `GET, POST` | `/api/v1/distribution-rules/{rule_id}/targets` |
| `DELETE, PATCH` | `/api/v1/distribution-rules/{rule_id}/targets/{target_id}` |
| `POST` | `/api/v1/distribution/trigger-run` |
| `GET` | `/api/v1/events/health` |
| `GET` | `/api/v1/events/subscribe` |
| `GET` | `/api/v1/favorites-sync/status` |
| `POST` | `/api/v1/favorites-sync/items/batch-retry` |
| `POST` | `/api/v1/favorites-sync/items/retry` |
| `POST` | `/api/v1/favorites-sync/preview` |
| `POST` | `/api/v1/favorites-sync/runs/{run_id}/retry` |
| `POST` | `/api/v1/favorites-sync/sync` |
| `GET` | `/api/v1/health` |
| `GET` | `/api/v1/init-status` |
| `GET` | `/api/v1/ai/capabilities` |
| `GET` | `/api/v1/media/{key}`（需要 API token） |
| `GET` | `/api/v1/platform-health` |
| `POST` | `/api/v1/platform-health/parse-test` |
| `GET` | `/api/v1/proxy/image` |
| `GET` | `/api/v1/pushed-records` |
| `DELETE` | `/api/v1/pushed-records/{record_id}` |
| `GET` | `/api/v1/render-config-presets` |
| `GET` | `/api/v1/render-config-presets/{preset_id}` |
| `GET` | `/api/v1/search/semantic` |
| `GET` | `/api/v1/search/semantic/index-status` |
| `POST` | `/api/v1/search/semantic/reindex` |
| `GET` | `/api/v1/settings` |
| `DELETE, GET, PUT` | `/api/v1/settings/{key}` |
| `POST` | `/api/v1/shares` |
| `GET` | `/api/v1/contents/{content_id}/processing-status` |
| `GET` | `/api/v1/storage/stats` |
| `GET` | `/api/v1/tags` |
| `GET` | `/api/v1/targets` |
| `POST` | `/api/v1/targets/batch-update` |
| `POST` | `/api/v1/targets/send-test` |
| `POST` | `/api/v1/targets/test` |
| `GET` | `/health` |

---

## 内容管理 API

### POST /api/v1/shares

提交分享链接并创建内容。

标签字段说明：
- `tags`: 快捷标签数组（可选）
- `tags_text`: 原始标签输入文本（可选）

服务端会统一对 `tags + tags_text` 做拆分、去空白与去重，支持逗号、中文逗号与空白分隔。

### GET /api/v1/contents

分页获取内容列表。

常用参数：

- `page` / `size`
- `platform` / `status` / `review_status`
- `tag` / `author`
- `start_date` / `end_date`
- `q` / `is_nsfw`

### GET /api/v1/contents/{id}

获取内容详情。

### PATCH /api/v1/contents/{id}

更新内容字段（如标签、审核状态、标题等）。

### DELETE /api/v1/contents/{id}

删除内容及关联记录。同时清理 `local://` 引用的本地媒体文件（含引用计数检查，仅在无其他内容引用时删除物理文件）。

### POST /api/v1/contents/{id}/re-parse

触发重新解析。

---

## 实时事件 SSE

### GET /api/v1/events/subscribe

SSE 订阅端点。

```javascript
const eventSource = new EventSource('/api/v1/events/subscribe');

eventSource.addEventListener('queue_updated', (e) => {
  const data = JSON.parse(e.data);
  console.log('queue updated', data);
});
```

当前实现中的主要事件：

- `connected`
- `ping`
- `content_created`
- `content_updated`
- `content_deleted`
- `content_pushed`
- `distribution_push_success`
- `distribution_push_failed`
- `queue_updated`
- `bot_sync_progress`
- `bot_sync_completed`

> 说明：事件总线为「进程内广播 + SQLite outbox 轮询同步」，用于多实例场景下事件传播。

### GET /api/v1/events/health

事件系统健康检查。

---

## 分发队列 API（/distribution-queue）

### GET /api/v1/distribution-queue/stats

获取队列状态统计（`will_push` / `filtered` / `pushed` 与 `due_now`）。

### GET /api/v1/distribution-queue/items

分页获取队列项。

返回项包含统一原因字段：

- `reason_code`：机器可读原因码（如 `manual_filtered`、`nsfw_blocked`、`already_pushed_dedupe`）
- `last_error`：面向展示的原因文案（可选）

查询参数：

- `status`（支持别名：`will_push`/`filtered`/`pushed`）
- `content_id`
- `rule_id`
- `bot_chat_id`
- `page`（默认 1）
- `size`（默认 50，最大 200）

### GET /api/v1/distribution-queue/items/{item_id}

获取单个队列项。

### POST /api/v1/distribution-queue/enqueue/{content_id}

手动入队。

请求体：

```json
{
  "force": false
}
```

### POST /api/v1/distribution-queue/items/{item_id}/retry

重试单个队列项。

请求体：

```json
{
  "reset_attempts": false
}
```

### POST /api/v1/distribution-queue/items/{item_id}/cancel

取消单个队列项。

### POST /api/v1/distribution-queue/batch-retry

批量重试队列项。

请求体：

```json
{
  "item_ids": [1, 2, 3],
  "status_filter": "failed",
  "limit": 100
}
```

### 内容维度操作

- `POST /api/v1/distribution-queue/content/{content_id}/status`
  - 支持状态：`will_push`、`filtered`
- `POST /api/v1/distribution-queue/content/{content_id}/reorder`
- `POST /api/v1/distribution-queue/content/{content_id}/push-now`
- `POST /api/v1/distribution-queue/content/{content_id}/schedule`
- `POST /api/v1/distribution-queue/content/batch-push-now`
- `POST /api/v1/distribution-queue/content/batch-reschedule`

### 队列项维度操作

- `POST /api/v1/distribution-queue/items/{item_id}/push-now`
- `POST /api/v1/distribution-queue/items/{item_id}/schedule`
- `POST /api/v1/distribution-queue/items/{item_id}/status`
- `POST /api/v1/distribution-queue/items/{item_id}/reorder`
- `POST /api/v1/distribution-queue/items/batch-push-now`
  - 请求体：`{"item_ids": [1, 2, 3]}`
  - 返回 `run_id`，运行结果进入 `recent_task_runs` 的 `distribution_schedule` 记录，`action=item_batch_push_now`。
- `POST /api/v1/distribution-queue/items/batch-schedule`
  - 请求体：`{"item_ids": [1, 2, 3], "start_time": "2026-06-05T12:00:00Z", "interval_seconds": 300}`

前端默认的单条与批量分发操作应使用队列项维度接口；内容维度接口只用于明确希望影响同一内容下所有目标队列项的批量操作。

---

## 分发规则 API

- `GET /api/v1/distribution-rules`
- `POST /api/v1/distribution-rules`
- `GET /api/v1/distribution-rules/{id}`
- `PATCH /api/v1/distribution-rules/{id}`
- `DELETE /api/v1/distribution-rules/{id}`

`POST /distribution-rules` 的请求体不包含 `targets`。
目标关联通过 `/api/v1/distribution-rules/{id}/targets` 系列接口管理。

### 分发目标 API

- `GET /api/v1/distribution-rules/{id}/targets`
- `POST /api/v1/distribution-rules/{id}/targets/backfill-preview`
- `POST /api/v1/distribution-rules/{id}/targets`
- `PATCH /api/v1/distribution-rules/{rule_id}/targets/{target_id}`
- `DELETE /api/v1/distribution-rules/{rule_id}/targets/{target_id}`

`POST /api/v1/distribution-rules/{id}/targets` 支持历史回填控制：

- `backfill_mode="new_only"`：默认值，仅对之后入库的内容生效。
- `backfill_mode="recent_days"` + `backfill_recent_days=N`：为最近 N 天内已解析并已审批、匹配规则的内容补建队列。
- `backfill_mode="all_history"`：为全部已解析并已审批、匹配规则的历史内容补建队列。

响应中的 `backfilled_count` 表示本次实际补建的队列项数量。
`POST /api/v1/distribution-rules/{id}/targets/backfill-preview` 接收同样的 `bot_chat_id`、`backfill_mode` 和 `backfill_recent_days`，只返回 `candidate_count`，不创建目标或队列项。

### 全局目标视图

- `GET /api/v1/targets`
- `POST /api/v1/targets/test`
- `POST /api/v1/targets/send-test`
- `POST /api/v1/targets/batch-update`

`GET /api/v1/targets` 返回的 `target_platform` 统一为 `telegram` 或 `qq`（不再暴露 `group/supergroup/channel/qq_group` 等 chat_type 细分值）。
`GET /api/v1/targets?platform=...` 与 `POST /api/v1/targets/batch-update` 的 `target_platform` 仅接受 `telegram|qq`。

---

## Bot 管理 API

### Bot Chat（运行时会话）

- `GET /api/v1/bot/chats`
- `POST /api/v1/bot/chats`
- `GET /api/v1/bot/chats/{chat_id}`
- `PATCH /api/v1/bot/chats/{chat_id}`
- `DELETE /api/v1/bot/chats/{chat_id}`
- `POST /api/v1/bot/chats/{chat_id}/toggle`
- `PUT /api/v1/bot/chats:upsert`
- `POST /api/v1/bot/chats/sync`
- `GET /api/v1/bot/status`
- `GET /api/v1/bot/runtime`

`POST /api/v1/bot/chats/sync` 会刷新 Telegram BotChat 元信息，支持可选 `chat_id` 只刷新单个目标。接口返回 `run_id`、`total/updated/failed/inaccessible` 和详情，并写入 `recent_task_runs` 的 `bot_chats_sync` 记录。健康矩阵的推送目标刷新会使用该 `run_id` 跳转到动态页日志。

`GET /api/v1/bot/status` 返回统一状态口径：
- `parse_stats`: `unprocessed` / `processing` / `parse_success` / `parse_failed`
- `distribution_stats`: `will_push` / `filtered` / `pushed`
- `rule_breakdown`: 按规则 ID 聚合的分发状态统计

其中 `parse_success` 为当前统一的解析成功物理状态。

`POST /api/v1/bot/chats` 与 `PUT /api/v1/bot/chats:upsert` 请求体必须包含 `bot_config_id`。

### Bot Config（账号配置）

- `POST /api/v1/bot-config`
- `GET /api/v1/bot-config`
- `PATCH /api/v1/bot-config/{id}`
- `DELETE /api/v1/bot-config/{id}`
- `POST /api/v1/bot-config/{id}/activate`
- `GET /api/v1/bot-config/{id}/qr-code`
- `POST /api/v1/bot-config/{id}/sync-chats`

`/bot-config/{id}/qr-code` 当前为单次查询（HTTP），不是 WebSocket 流。
`/bot/chats/sync` 使用已启用且 `is_primary=true` 的 Telegram BotConfig。
QQ 配置支持字段：`napcat_http_url`、`napcat_ws_url`、`napcat_access_token`。

升级旧数据时，先执行：`python -m migrations.m14_bind_bot_chats_to_config`。
若为较早版本数据库，再执行：`python -m migrations.m15_add_napcat_access_token`。

---

## 系统 API

- `GET /api/v1/tags`
- `GET /api/v1/dashboard/stats`
- `GET /api/v1/dashboard/queue`
- `GET /api/v1/health`
- `GET /health`

`GET /api/v1/dashboard/queue` 返回：
- `parse`: 解析阶段四态统计（`unprocessed`/`processing`/`parse_success`/`parse_failed`）
- `distribution`: 解析成功后的分发三态统计（`will_push`/`filtered`/`pushed`）

`GET /api/v1/health` 与 `GET /health` 返回同一结构，除 `db/queue/fts` 外还包含：

- `checks.workers`: 解析 worker 与分发队列 worker 的配置数量。
- `checks.providers`: text LLM、vision LLM、summary、embedding、Agent chat 与 Bot 配置状态；AI 配置由 typed `ConfigService` 汇总，包含 text/vision model/base URL、summary 启用状态/model/api version、embedding model/dim/search limit、Agent chat model/base URL。
- `checks.background_tasks`: 解析任务表、分发队列、Discovery 同步源的 pending/failed/retry 统计与最近成功时间。
- `checks.background_tasks.task_states`: 后台任务持久化状态，包含 `last_started_at`、`last_success_at`、`last_error_at`、`last_error`、`run_count`、`error_count`。

`GET /api/v1/background-tasks/diagnostics` 额外返回：

- `recent_task_runs`: 最近后台任务运行记录。当前覆盖 `ai_connectivity_test`、`bot_chats_sync`、`content_parse`、`content_embedding`、`content_reparse`、`content_summary`、`discovery_patrol`、`discovery_source_test`、`discovery_sync`、`distribution_push`、`distribution_schedule`、`distribution_target_test`、`distribution_target_send_test`、`distribution_worker_poll`、`favorites_sync`、`platform_parse_test` 和 `semantic_reindex`，包含 `run_id`、`task`、`status`、`started_at`、`finished_at`、`error`、`trigger` 以及任务特定元数据。
- `failed_parse_tasks`、`failed_distribution_items`、`failed_discovery_sources`: 仍用于展示可恢复或需排查的失败对象。

`favorites_sync` 运行记录的 `result` 会包含平台级 `fetched/imported/skipped/failed` 汇总；导入阶段发生单条失败时，平台结果还会返回最多 50 条 `failed_items` 诊断记录，并提供 `failed_items_total` 与 `failed_items_truncated`。单条失败字段包含 `url`、`title`、`item_id`、`error`、`error_code`，用于前端解释失败来源，也可作为单条失败重试输入。

`GET /api/v1/favorites-sync/status` 会返回 `policies.duplicate_strategy` 和 `policies.unfavorite_strategy`。当前重复策略支持 `merge`（默认，合并已有内容来源并执行必要后处理）和 `skip`（导入阶段跳过本地已存在 canonical URL）；同步 run 结果会记录 `duplicate_strategy` 与 `duplicate_skipped`。`unfavorite_strategy` 当前固定为 `keep_local`，表示不会因为远端取消收藏自动删除本地内容。

`POST /api/v1/favorites-sync/items/retry` 会对单条失败收藏候选重新执行入库：请求包含 `platform`、`url`，可选 `title`、`item_id`、`source_run_id`。接口不重新拉取收藏夹、不推进平台同步 cursor；成功返回 `run_id` 与 `content_id`，并写入 `recent_task_runs` 的 `favorites_sync` 记录，`trigger=item_retry`。

`POST /api/v1/favorites-sync/items/batch-retry` 会在一个可观察 run 中批量重试失败收藏候选：请求包含 `platform`、`items[]` 和可选 `source_run_id`，单次最多 50 条。接口返回 `run_id`、`imported/skipped/failed` 与逐项结果，运行记录写入 `favorites_sync`，`trigger=item_batch_retry`。该接口同样不重新拉取收藏夹、不推进平台同步 cursor。

`POST /api/v1/discovery/sources/{source_id}/sync` 返回 `202 Accepted`，响应包含 `run_id`。若发现同步任务实例未运行，返回 `503 discovery_task_unavailable`；若来源类型尚未实现，返回 `400 source_kind_not_supported`。

`POST /api/v1/discovery/sources/{source_id}/test` 会对发现源执行一次只读质量检查：调用对应 scraper 拉取候选，但不写入内容、不更新 `last_sync_at`、不推进 cursor。接口返回 `ok`、`status`、`run_id`、候选数量、最多 5 条样本、是否产生 cursor 和耗时；成功、空结果或失败都会写入 `recent_task_runs` 的 `discovery_source_test` 记录。

`POST /api/v1/search/semantic/reindex` 在 `dry_run=false` 时会调度后台语义索引任务并返回 `run_id`；`dry_run=true` 只返回候选数量和预计 embedding 调用数，不创建运行记录。

解析、发现或导入后的单条自动 Embedding 入库会产生 `content_embedding` 运行记录；它通常不由前端直接触发，但可在 `recent_task_runs` 中排查某条内容是否完成语义索引。

`POST /api/v1/search/semantic/embeddings/{embedding_id}/retry` 会按单条 `content_embeddings` 记录重试对应语义分块，并返回 `run_id`；运行结果进入 `recent_task_runs` 的 `semantic_reindex` 记录，`scope=embedding`。若远端 embedding 调用仍失败，接口返回 `503`，同时记录失败 run。

发现缓冲区的自动巡逻评分会产生 `discovery_patrol` 运行记录，记录候选数量、成功评分数量、失败数量与兴趣画像是否存在；它用于排查探索库内容为何未进入可见状态或评分后处理是否中断。

`POST /api/v1/contents/{content_id}/patrol-score` 会为单条发现流内容手动触发巡逻评分并返回 `run_id`；运行结果进入 `recent_task_runs` 的 `discovery_patrol` 记录，`trigger=manual`，并记录 `content_id`、评分结果和失败数量。非发现流内容返回 `400`。

`POST /api/v1/ai/connectivity-test` 会对 AI 能力执行一次真实连通性测试，`target` 支持 `agent_chat`、`text_llm`、`vision_llm`、`summary_generation` 和 `semantic_search`，其中 `agent` 可作为 `agent_chat` 的别名。接口返回 `ok`、`run_id`、耗时和错误摘要；成功或失败都会写入 `recent_task_runs` 的 `ai_connectivity_test` 记录，用于区分“未配置”和“已配置但真实调用不可用”。

`POST /api/v1/platform-health/parse-test` 会对指定平台和 URL 执行一次真实解析测试，`platform` 使用平台枚举值，`url` 必须是 HTTP(S)。接口不会创建收藏内容，也不会推进同步 cursor；成功返回标题、内容类型、布局类型、作者、媒体数量、耗时和 `run_id`，成功或失败都会写入 `recent_task_runs` 的 `platform_parse_test` 记录。

`POST /api/v1/targets/test` 会对推送目标执行一次连接测试：Telegram 目标验证 bot 是否能访问 chat，QQ 目标验证 Napcat 是否能读取群信息。接口返回 `status`、`message`、`run_id`、耗时和目标元数据；成功或失败都会写入 `recent_task_runs` 的 `distribution_target_test` 记录。该接口不会发送测试消息。

`POST /api/v1/targets/send-test` 会向推送目标发送一条固定诊断消息，用于验证目标是否能真实接收推送。接口返回 `status`、`message`、`run_id`、耗时和 `details.message_id`；成功或失败都会写入 `recent_task_runs` 的 `distribution_target_send_test` 记录。该接口不创建 `PushedRecord`，也不更新正常内容分发统计。

解析主队列消费分享/导入后的解析任务时会产生 `content_parse` 运行记录，记录 `content_id`、`task_id`、队列动作、重试参数、跳过原因或解析后的状态；它区别于手动重新解析接口产生的 `content_reparse`。

`POST /api/v1/contents/{content_id}/re-parse` 会调度后台重新解析任务并返回 `run_id`；运行结果进入 `recent_task_runs` 的 `content_reparse` 记录。

`POST /api/v1/contents/{content_id}/generate-summary` 会执行摘要生成并返回 `run_id`；运行结果进入 `recent_task_runs` 的 `content_summary` 记录。

`POST /api/v1/distribution-queue/items/{item_id}/push-now` 会立即处理单个分发队列项并返回 `run_id`；运行结果进入 `recent_task_runs` 的 `distribution_push` 记录。

`POST /api/v1/distribution-queue/content/{content_id}/push-now` 与 `POST /api/v1/distribution-queue/content/batch-push-now` 会把相关队列项调整为立即可处理并返回 `run_id`；运行结果进入 `recent_task_runs` 的 `distribution_schedule` 记录。它们是排期/调度操作，不代表外部推送已经成功。

分发队列 worker 每次自动领取到期队列项时会产生 `distribution_worker_poll` 运行记录，记录 worker 名称、领取项、处理数量、异常数量和最终队列状态分布；空轮询不会产生记录。

---

## 常见状态码

- `200 OK`
- `201 Created`
- `400 Bad Request`
- `401 Unauthorized`
- `404 Not Found`
- `500 Internal Server Error`
