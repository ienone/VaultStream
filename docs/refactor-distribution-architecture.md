# 分发系统架构说明（当前实现）

本文档描述 Review/Distribution 模块的当前实现与约束，仅包含现网逻辑。

## 1. 核心模型

| 模型 | 存储 | 职责 |
|---|---|---|
| `DistributionRule` | `distribution_rules` | 定义匹配条件与分发策略 |
| `DistributionTarget` | `distribution_targets` | 维护 Rule 与 BotChat 的目标关联及目标级配置 |
| `BotChat` | `bot_chats` | 维护群组/频道身份、可达性、权限与统计 |
| `ContentQueueItem` | `content_queue_items` | 分发执行队列，承载调度/重试/状态流转 |

---

## 2. 职责边界

### 2.1 DistributionRule

负责“匹配什么内容”。

主要字段：
- `match_conditions`
- `nsfw_policy`
- `render_config`
- `priority`
- `enabled`
- `approval_required`
- `auto_approve_conditions`
- `rate_limit`
- `time_window`

### 2.2 DistributionTarget

负责“发到哪里、如何发”。

主要字段：
- `rule_id`
- `bot_chat_id`
- `enabled`
- `merge_forward`
- `use_author_name`
- `summary`
- `render_config_override`

渲染配置优先级：
`target.render_config_override` > `rule.render_config` > 系统默认。

### 2.3 BotChat

负责“目标身份与可达性状态”。

主要字段：
- `chat_id`, `chat_type`
- `title`, `username`, `description`
- `enabled`
- `is_accessible`
- `is_admin`, `can_post`
- `nsfw_chat_id`
- `total_pushed`, `last_pushed_at`

---

## 3. 执行链路

1. 引擎按 `DistributionRule.match_conditions` 匹配内容。
2. 通过 `DistributionTarget` 展开目标并生成/更新 `ContentQueueItem`。
3. `queue_worker` 消费到期队列项并执行平台推送。
4. 推送结果回写到 `ContentQueueItem` 与 `PushedRecord`。
5. 事件通过 `EventBus` 推送到 SSE 订阅端。

---

## 4. API 约定

### 4.1 规则与目标

- `GET /api/v1/distribution-rules`
- `POST /api/v1/distribution-rules`
- `GET /api/v1/distribution-rules/{id}`
- `PATCH /api/v1/distribution-rules/{id}`
- `DELETE /api/v1/distribution-rules/{id}`

- `GET /api/v1/distribution-rules/{rule_id}/targets`
- `POST /api/v1/distribution-rules/{rule_id}/targets`
- `PATCH /api/v1/distribution-rules/{rule_id}/targets/{target_id}`
- `DELETE /api/v1/distribution-rules/{rule_id}/targets/{target_id}`

### 4.2 队列管理

- `GET /api/v1/distribution-queue/stats`
- `GET /api/v1/distribution-queue/items`
- `GET /api/v1/distribution-queue/items/{item_id}`
- `POST /api/v1/distribution-queue/items/{item_id}/push-now`
- `POST /api/v1/distribution-queue/items/{item_id}/retry`
- `POST /api/v1/distribution-queue/batch-retry`

内容维度操作：
- `POST /api/v1/distribution-queue/content/{content_id}/status`
- `POST /api/v1/distribution-queue/content/{content_id}/reorder`
- `POST /api/v1/distribution-queue/content/{content_id}/push-now`
- `POST /api/v1/distribution-queue/content/{content_id}/schedule`
- `POST /api/v1/distribution-queue/content/batch-push-now`
- `POST /api/v1/distribution-queue/content/batch-reschedule`
- `POST /api/v1/distribution-queue/content/merge-group`

---

## 5. 运行时约束

- 去重依据：`PushedRecord (content_id, target_id)`。
- 状态流：`pending/scheduled/processing/success/failed/skipped/canceled`。
- 多实例实时同步：`realtime_events` + SSE。
- 手动推送优先入口：`/distribution-queue/items/{item_id}/push-now`。

---

## 6. 验证清单

- Rule/Target CRUD 可用。
- 队列项可查询、可重试、可即时推送。
- Worker 成功回写 `message_id` 与 `completed_at`。
- 失败场景回写 `last_error*` 与 `next_attempt_at`。
- 前端规则编辑、目标编辑、队列操作全链路可用。
