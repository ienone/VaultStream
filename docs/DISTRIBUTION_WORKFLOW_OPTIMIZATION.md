# 分发系统架构优化与完整流程设计

> 文档创建时间: 2026-02-13  
> 最后更新: 2026-02-13  
> 实施状态: 第一阶段（P0）+ 第二阶段（P1 业务流程）+ 第三阶段（P1 体验优化）已完成 ✅

---

## 1. 当前架构（代码对齐版）

分发链路已统一为以下主干：

1. `DistributionEngine`：规则匹配、审批判断、生成队列项。
2. `queue_service.enqueue_content`：内容入队入口（手动/自动复用）。
3. `ContentQueueItem`：三元组队列模型（`content_id × rule_id × bot_chat_id`）。
4. `queue_worker`：按状态轮询并执行推送，负责重试与结果回写。
5. `event_bus`：SSE 事件发布，支持多实例（SQLite outbox 同步）。

---

## 2. 核心模型

### 2.1 QueueItemStatus

当前状态枚举：

- `pending`
- `scheduled`
- `processing`
- `success`
- `failed`
- `skipped`
- `canceled`

### 2.2 ContentQueueItem（关键字段）

```python
class ContentQueueItem(Base):
    __tablename__ = "content_queue_items"

    id = Column(Integer, primary_key=True)

    content_id = Column(Integer, ForeignKey("contents.id"), nullable=False)
    rule_id = Column(Integer, ForeignKey("distribution_rules.id"), nullable=False)
    bot_chat_id = Column(Integer, ForeignKey("bot_chats.id"), nullable=False)

    target_platform = Column(String(20), nullable=False)
    target_id = Column(String(200), nullable=False)

    status = Column(SQLEnum(QueueItemStatus), default=QueueItemStatus.PENDING)
    priority = Column(Integer, default=0)
    scheduled_at = Column(DateTime)

    rendered_payload = Column(JSON)
    nsfw_routing_result = Column(JSON)
    passed_rate_limit = Column(Boolean, default=True)
    rate_limit_reason = Column(String(200))

    needs_approval = Column(Boolean, default=False)
    approved_at = Column(DateTime)
    approved_by = Column(String(100))

    attempt_count = Column(Integer, default=0)
    max_attempts = Column(Integer, default=3)
    next_attempt_at = Column(DateTime)

    locked_at = Column(DateTime)
    locked_by = Column(String(100))

    message_id = Column(String(200))
    last_error = Column(Text)
    last_error_type = Column(String(200))
    last_error_at = Column(DateTime)

    started_at = Column(DateTime)
    completed_at = Column(DateTime)
```

> 说明：当前模型使用 `completed_at`。

---

## 3. API 新实践（统一规范）

### 3.1 队列 API

统一使用 `/api/v1/distribution-queue/*`：

- `GET /distribution-queue/stats`
- `GET /distribution-queue/items`
- `GET /distribution-queue/items/{item_id}`
- `POST /distribution-queue/enqueue/{content_id}`
- `POST /distribution-queue/items/{item_id}/retry`
- `POST /distribution-queue/items/{item_id}/cancel`
- `POST /distribution-queue/batch-retry`

内容维度操作：

- `POST /distribution-queue/content/{content_id}/status`
- `POST /distribution-queue/content/{content_id}/reorder`
- `POST /distribution-queue/content/{content_id}/push-now`
- `POST /distribution-queue/content/{content_id}/schedule`
- `POST /distribution-queue/content/batch-push-now`
- `POST /distribution-queue/content/batch-reschedule`
- `POST /distribution-queue/content/merge-group`

> `merge-group` 返回语义化成功响应。

### 3.2 Bot 相关 API

- Bot Chat：`/api/v1/bot/chats/*`，同步入口为 `POST /api/v1/bot/chats/sync`
- Bot Config：`/api/v1/bot-config/*`，支持 `activate` / `qr-code` / `sync-chats`

`GET /api/v1/bot-config/{id}/qr-code` 当前为 HTTP 单次查询，不是 WebSocket 流。

---

## 4. 完整流程

### 阶段 A：配置 Bot 与会话

1. 创建 Bot 配置（`POST /bot-config`）。
2. 同步会话（`POST /bot-config/{id}/sync-chats`）。
3. 在规则中关联目标（创建规则时 `targets` 或后续 target API）。

### 阶段 B：规则匹配与入队

1. 内容进入 `pulled`（含审批待处理内容）。
2. `DistributionEngine` 匹配规则与目标。
3. 生成 `ContentQueueItem`（按三元组拆分）。
4. 若规则 `approval_required=true`，队列项进入 `pending`，等待人工放行。

### 阶段 C：人工操作与排期

前端通过 `/distribution-queue/content/*` 进行：

- 状态切换（`will_push` / `filtered`）
- 重排（`reorder`）
- 立即推送（`push-now`）
- 定时推送（`schedule`）
- 批量推送与批量重排期

### 阶段 D：Worker 推送执行

1. Worker 拉取 `scheduled` 且到期任务。
2. 执行推送并更新 `processing → success/failed`。
3. 写回 `message_id` / `last_error` / `completed_at`。
4. 发布 `queue_updated`、`distribution_push_success`、`distribution_push_failed` 等事件。

---

## 5. 实时事件链路

### 5.1 SSE 端点

- `GET /api/v1/events/subscribe`
- `GET /api/v1/events/health`

### 5.2 关键事件

- `queue_updated`
- `content_pushed`
- `distribution_push_success`
- `distribution_push_failed`
- `bot_sync_progress`
- `bot_sync_completed`

### 5.3 多实例一致性

当前 `EventBus` 采用：

- 本地进程内广播（低延迟）
- SQLite `realtime_events` outbox + 轮询消费（跨实例传播）

该实现通过本地广播与 SQLite outbox 组合，保证多实例事件可见性。

---

## 6. 已完成优化清单

- 队列接口统一迁移至 `/distribution-queue/*`。
- 前端 Review/Queue Provider 已切换新接口。
- 审批路径已可达：`pending` 内容可入 `approval_required` 规则队列。
- 实时事件已支持跨实例传播。
- 文档示例统一使用 `/distribution-queue/*` 与 SSE 描述。

---

## 7. 维护约定

后续文档变更请遵循：

1. 以 `backend/app/routers/distribution_queue.py` 与 `backend/app/core/events.py` 为单一事实源。
2. 队列能力统一扩展 `/distribution-queue/*`。
3. 所有“完成时间”字段统一使用 `completed_at`。
4. 实时能力描述统一使用 SSE。
