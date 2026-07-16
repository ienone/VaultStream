# OpenAPI 端点清单

## 文档状态

active

> 本文件由 `scripts/export_openapi_endpoints.py` 从当前 FastAPI OpenAPI 生成，不手工补写行为说明。

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
| `GET` | `/api/v1/ai/capabilities` |
| `POST` | `/api/v1/ai/connectivity-test` |
| `GET` | `/api/v1/background-tasks/diagnostics` |
| `GET` | `/api/v1/background-tasks/metrics` |
| `GET` | `/api/v1/background-tasks/runs/{run_id}` |
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
| `POST` | `/api/v1/contents/{content_id}/patrol-score` |
| `GET` | `/api/v1/contents/{content_id}/processing-status` |
| `POST` | `/api/v1/contents/{content_id}/re-parse` |
| `POST` | `/api/v1/contents/{content_id}/retry` |
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
| `POST` | `/api/v1/distribution-queue/items/batch-push-now` |
| `POST` | `/api/v1/distribution-queue/items/batch-schedule` |
| `GET` | `/api/v1/distribution-queue/items/{item_id}` |
| `POST` | `/api/v1/distribution-queue/items/{item_id}/cancel` |
| `POST` | `/api/v1/distribution-queue/items/{item_id}/push-now` |
| `POST` | `/api/v1/distribution-queue/items/{item_id}/reorder` |
| `POST` | `/api/v1/distribution-queue/items/{item_id}/retry` |
| `POST` | `/api/v1/distribution-queue/items/{item_id}/schedule` |
| `POST` | `/api/v1/distribution-queue/items/{item_id}/status` |
| `GET` | `/api/v1/distribution-queue/stats` |
| `GET, POST` | `/api/v1/distribution-rules` |
| `GET` | `/api/v1/distribution-rules/preview/stats` |
| `DELETE, GET, PATCH` | `/api/v1/distribution-rules/{rule_id}` |
| `GET` | `/api/v1/distribution-rules/{rule_id}/preview` |
| `GET, POST` | `/api/v1/distribution-rules/{rule_id}/targets` |
| `POST` | `/api/v1/distribution-rules/{rule_id}/targets/backfill-preview` |
| `DELETE, PATCH` | `/api/v1/distribution-rules/{rule_id}/targets/{target_id}` |
| `POST` | `/api/v1/distribution/trigger-run` |
| `GET` | `/api/v1/events/health` |
| `GET` | `/api/v1/events/subscribe` |
| `POST` | `/api/v1/favorites-sync/items/batch-retry` |
| `POST` | `/api/v1/favorites-sync/items/retry` |
| `POST` | `/api/v1/favorites-sync/preview` |
| `POST` | `/api/v1/favorites-sync/runs/{run_id}/retry` |
| `GET` | `/api/v1/favorites-sync/status` |
| `POST` | `/api/v1/favorites-sync/sync` |
| `GET` | `/api/v1/health` |
| `GET` | `/api/v1/init-status` |
| `GET` | `/api/v1/media/{key}` |
| `GET` | `/api/v1/platform-health` |
| `POST` | `/api/v1/platform-health/parse-test` |
| `GET` | `/api/v1/proxy/image` |
| `GET` | `/api/v1/pushed-records` |
| `DELETE` | `/api/v1/pushed-records/{record_id}` |
| `GET` | `/api/v1/render-config-presets` |
| `GET` | `/api/v1/render-config-presets/{preset_id}` |
| `GET` | `/api/v1/search/semantic` |
| `POST` | `/api/v1/search/semantic/embeddings/{embedding_id}/retry` |
| `GET` | `/api/v1/search/semantic/index-status` |
| `POST` | `/api/v1/search/semantic/reindex` |
| `GET` | `/api/v1/settings` |
| `DELETE, GET, PUT` | `/api/v1/settings/{key}` |
| `POST` | `/api/v1/shares` |
| `GET` | `/api/v1/storage/stats` |
| `GET` | `/api/v1/tags` |
| `GET` | `/api/v1/targets` |
| `POST` | `/api/v1/targets/batch-update` |
| `POST` | `/api/v1/targets/send-test` |
| `POST` | `/api/v1/targets/test` |
| `GET` | `/health` |
