# 数据库领域：任务、自动化与分发

## 文档状态

active

## ORM 来源

- `backend/app/models/system.py`
- `backend/app/models/distribution.py`
- `backend/app/models/bot.py`

## 系统与任务

- `tasks` 保存解析等持久化任务的类型、载荷、状态、优先级、重试与时间戳。
- `system_settings` 以 key 和 JSON value 保存持久化配置，并记录分类、说明和更新时间。
- `background_task_runs` 以全局 `run_id` 保存一次可观察运行；`notification_messages` 保存从可靠运行结果产生的去重消息和用户已读、静默、稍后、移除状态。

任务表与 recent run 诊断不是同一概念：前者承担队列/持久化执行，后者面向用户观察一次具体运行。
消息表也不替代运行账本：它只保存值得进入用户收件箱的回执或异常，并通过 `source_type`、`source_id` 和 payload 关联事实资源。

## 分发规则与目标

- `distribution_rules` 保存匹配条件、优先级、NSFW 策略、审批要求、频率限制和默认渲染配置。
- `distribution_targets` 把规则关联到 BotChat，并保存启用状态、历史回填水位和目标级渲染覆盖。

规则本身不内嵌目标列表。删除规则或 BotChat 时，目标关联使用数据库级联关系清理。

## `content_queue_items`

队列项按内容、规则和 BotChat 组合建模，主要字段组为：

| 职责 | 主要字段 |
| :--- | :--- |
| 目标 | `content_id`、`rule_id`、`bot_chat_id`、`target_platform`、`target_id` |
| 状态与排期 | `status`、`priority`、`scheduled_at` |
| 渲染与策略 | `rendered_payload`、`nsfw_routing_result`、`passed_rate_limit`、`rate_limit_reason`、`approved_by` |
| 重试与锁 | `attempt_count`、`max_attempts`、`next_attempt_at`、`locked_at`、`locked_by` |
| 结果 | `message_id`、`last_error*`、`started_at`、`completed_at` |

队列状态、外部发送结果和用户可见运行状态必须保持可区分，不能用一个字段同时表达三者。

## 推送记录

`pushed_records` 保存内容、目标、外部 message ID、发送状态、错误和时间，用于历史展示与去重。测试消息不写入该表。

## Bot 配置

- `bot_configs` 保存 Telegram 或 Napcat 连接配置、启用/主配置状态和 Bot 身份。
- `bot_chats` 保存某个配置发现的群组或频道、权限、用途开关、同步状态和推送统计。
- `bot_runtime` 保存进程运行身份、心跳、版本与最近错误。

凭证字段属于敏感数据。文档只描述职责，不记录真实值；导出、日志和测试夹具不得包含生产 token。

## 关键一致性

- 队列项的唯一业务边界是内容、规则、目标组合。
- worker 领取和更新队列项时必须维护锁、重试次数和最终状态的一致性。
- 删除 BotConfig 前必须遵守 BotChat 级联关系，并确认不会留下仍被分发目标引用的孤儿状态。
