# VaultStream API 文档

> 版本: v0.3.1  
> 更新: 2026-02-13  
> 本文档按当前代码实现更新（SSE + ContentQueueItem + /distribution-queue/*）

---

## 鉴权

所有 `/api/v1/*` 请求支持以下任一方式携带 Token：

- `X-API-Token: <token>`
- `Authorization: Bearer <token>`

未配置 `API_TOKEN` 时可跳过鉴权（仅建议本地开发）。

---

## 内容管理 API

### POST /api/v1/shares

提交分享链接并创建内容。

### GET /api/v1/contents

分页获取内容列表。

常用参数：

- `page` / `size`
- `platform` / `status` / `review_status`
- `tag` / `author`
- `start_date` / `end_date`
- `q` / `is_nsfw`
- `exclude_fields`（默认排除大字段）

### GET /api/v1/contents/{id}

获取内容详情。

### PATCH /api/v1/contents/{id}

更新内容字段（如标签、审核状态、标题等）。

### DELETE /api/v1/contents/{id}

删除内容及关联记录。

### POST /api/v1/contents/{id}/re-parse

触发重新解析。

### 批量内容 API

- `POST /api/v1/contents/batch-update`
- `POST /api/v1/contents/batch-delete`
- `POST /api/v1/contents/batch-re-parse`

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

获取队列状态统计（`will_push` / `filtered` / `pending_review` / `pushed` 与 `due_now`）。

### GET /api/v1/distribution-queue/items

分页获取队列项。

查询参数：

- `status`（支持别名：`will_push`/`filtered`/`pending_review`/`pushed`）
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
- `POST /api/v1/distribution-queue/content/merge-group`

### 队列项维度操作

- `POST /api/v1/distribution-queue/items/{item_id}/push-now`

`merge-group` 在 `ContentQueueItem` 模型下返回语义化成功响应。

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
- `POST /api/v1/distribution-rules/{id}/targets`
- `PATCH /api/v1/distribution-rules/{rule_id}/targets/{target_id}`
- `DELETE /api/v1/distribution-rules/{rule_id}/targets/{target_id}`

### 全局目标视图

- `GET /api/v1/targets`
- `POST /api/v1/targets/test`
- `POST /api/v1/targets/batch-update`

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

`GET /api/v1/bot/status` 返回统一状态口径：
- `parse_stats`: `unprocessed` / `processing` / `parse_success` / `parse_failed`
- `distribution_stats`: `will_push` / `filtered` / `pending_review` / `pushed`
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
- `GET /health`

`GET /api/v1/dashboard/queue` 返回：
- `parse`: 解析阶段四态统计（`unprocessed`/`processing`/`parse_success`/`parse_failed`）
- `distribution`: 解析成功后的分发四态统计（`will_push`/`filtered`/`pending_review`/`pushed`）

---

## 常见状态码

- `200 OK`
- `201 Created`
- `400 Bad Request`
- `401 Unauthorized`
- `404 Not Found`
- `500 Internal Server Error`
