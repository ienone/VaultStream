# 内容推送逻辑详解（当前实现）

本文档说明 VaultStream 当前分发推送主流程，按 `ContentQueueItem` 队列模型与 `queue_worker` 实现对齐。

---

## 1. 核心组件

- `DistributionEngine` (`backend/app/distribution/engine.py`)
  - 规则匹配、审批判定、队列刷新。
- `queue_service` (`backend/app/distribution/queue_service.py`)
  - 入队入口，负责生成队列项与触发队列更新事件。
- `queue_worker` (`backend/app/distribution/queue_worker.py`)
  - 消费已排期任务并执行推送。
- `PushService` (`backend/app/push/*`)
  - 平台推送实现（Telegram / QQ）。
- `EventBus` (`backend/app/core/events.py`)
  - SSE 事件发布 + SQLite outbox 跨实例同步。

---

## 2. 端到端流程

### 2.1 入队

1. 内容满足基础条件后进入匹配。
2. 引擎按规则筛选并展开目标（`rule × bot_chat`）。
3. 生成/更新 `ContentQueueItem`，初始为 `pending` 或 `scheduled`。
4. 发布 `queue_updated` 事件。

### 2.2 审批与人工操作

人工审批与调度统一走 `/api/v1/distribution-queue/content/*`：

- `status`（`will_push` / `filtered`）
- `reorder`
- `push-now`
- `schedule`
- `batch-push-now`
- `batch-reschedule`

### 2.3 推送执行

1. Worker 领取到期 `scheduled` 项并加锁。
2. 执行平台推送。
3. 成功：`status=success`，回写 `message_id`、`completed_at`。
4. 失败：`status=failed`，回写 `last_error`、`last_error_type`、`last_error_at`，并计算重试。
5. 发布：`queue_updated`、`distribution_push_success`、`distribution_push_failed`、`content_pushed`。

---

## 3. 队列状态语义

- `pending`: 待审批或待进一步处理。
- `scheduled`: 已进入排期，等待执行。
- `processing`: Worker 正在处理。
- `success`: 推送完成。
- `failed`: 推送失败，允许重试。
- `skipped`: 因策略/去重等跳过。
- `canceled`: 人工取消。

---

## 4. 实时更新机制

前端通过 SSE 订阅 `/api/v1/events/subscribe`。

- 单实例：事件实时广播到本地订阅者。
- 多实例：事件写入 `realtime_events`，由其他实例轮询消费并转发。

该机制保证队列/推送状态在多实例部署下仍可被前端实时感知。

---

## 5. 关键接口约定

- 队列管理入口统一使用 `/api/v1/distribution-queue/*`。
- Bot 手动触发使用队列项粒度接口：`POST /api/v1/distribution-queue/items/{item_id}/push-now`。
- 队列完成时间字段为 `completed_at`。
- Bot 二维码接口为 HTTP 查询。

---

## 6. 排查建议

1. `GET /api/v1/distribution-queue/stats` 查看整体状态分布与 `due_now`。
2. `GET /api/v1/distribution-queue/items?status=failed` 定位失败项。
3. 结合后端日志查看 `last_error` 与平台返回。
4. 用 `POST /api/v1/distribution-queue/items/{item_id}/retry` 或 `batch-retry` 回放。
