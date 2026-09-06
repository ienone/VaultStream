# 后端模块：消息盒子

## 文档状态

active

## 代码位置

- Model: `backend/app/models/system.py::NotificationMessage`
- Service: `backend/app/services/notification_inbox.py`
- Digest service: `backend/app/services/notification_digest.py`
- Digest task: `backend/app/tasks/notification_digest.py`
- Router: `backend/app/routers/notifications.py`
- Schema: `backend/app/schemas/notifications.py`
- Migration: `backend/migrations/m31_notification_inbox.py`

## 当前职责

消息盒子持久化用户可处理的系统消息，不把 SSE 事件或后台运行账本本身当成消息。当前可靠接入来源为：所有后台运行失败，`manual`、`retry`、`user`、`api` 触发的成功回执，等待用户决定的 Agent confirmation（包括 Telegram Bot `/ai` 发起的确认），Telegram Bot `/save` 已成功持久化的链接、文字或附件回执，已保存但无法通过校验的平台账号，以及基于持久化动态和进行中知识事件的周期摘要。普通定时调度成功仍只进入运行账本，不制造收件箱噪音。

同一任务与关联内容、来源、平台或目标的重复失败使用稳定 `dedupe_key` 合并，并累计 `occurrence_count`；新的失败会重新变成未读。成功回执按 `run_id` 独立记录并在 30 天后过期。消息保留完整来源类型、来源 ID、关联 payload 和语义路由，但列表中的主要动作只跳转到对应任务详情。

已读、静默、稍后提醒、移除与恢复都是持久化状态。Agent confirmation 使用 confirmation ID 去重并深链到 `/agent?session_id=...`；批准、拒绝、执行失败、停止 run、清空或删除 session 后更新其状态并自动标记已读、移除。`tg-*` 会话的确认保留 `telegram_bot` origin 和独立 source type，既能在 Bot 按钮中决定，也能回到应用 Agent 会话处理。未读计数排除静默、未来提醒、已移除和已过期消息。`notification_updated` 只承载刷新提示，不包含完整消息或时间对象；客户端收到后重新读取 API。

平台账号消息由手动有效性检测、二维码登录完成、主动退出和 Cookie 保活结果驱动，使用平台 ID 去重并跳转 `/accounts`。未配置凭据不是异常，不创建消息；同一失效状态反复检查不增加次数或重新唤醒已处理消息；校验恢复或主动清除凭据后自动移出，之后再次失效才作为新的 occurrence 重新提醒。通知写入失败只记录结构化警告，不改变认证检查本身的返回值。

Bot 捕获回执由 `ContentService` 在内容提交成功后投影，不允许 Bot 绕过内容 API 直接写消息表。回执按内容 ID 去重，区分链接、文字和附件，深链 `/collection/{content_id}`，30 天后过期；消息 payload 只复制 chat/message/media group/附件类型等最小来源字段。通知写入失败不改变捕获结果；内容删除后对应回执自动标记已读并移出活动消息。普通聊天、下载失败和未持久化的请求不生成回执。

周期摘要由 leader 任务读取 `enable_notification_digest` 与 `notification_digest_interval_hours`，只汇总上个检查窗口内已经持久化的 discovery 候选和 active knowledge event 变化，并在 payload 中保留内容、事件 ID 与语义路由。空窗口只推进游标，不创建占位消息；手动生成 API 复用同一生产者。该摘要是确定性的事实汇总，不代表模型生成的事件综合或智能摘要。

## API

- `GET /api/v1/notifications`：按 category/state 分页读取消息及全局未读数。
- `POST /api/v1/notifications/{notification_id}/actions`：执行 read、unread、mute、unmute、snooze、unsnooze、dismiss、restore。
- `POST /api/v1/notifications/read-all`：把当前可见未读消息标为已读。
- `POST /api/v1/notifications/digest`：立即检查一次持久化活动窗口；返回是否创建消息及动态、事件计数。

## 当前边界

Bot 发起的 Agent 确认和显式 `/save` 成功回执已经成为消息生产者，但普通 Bot 对话仍不进入消息盒子；账号当前只接入平台认证有效性，不代表收藏同步、账号权限和 Bot 身份都已覆盖。周期摘要只陈述持久化活动计数和最近标题，不替代自动事件生产、RAG 或模型综合。Agent 当前只接入工具 confirmation，不代表通用对话消息都进入收件箱。消息盒子动作只改变收件箱状态，不能直接批准 confirmation；用户必须进入所属 Agent 会话，或在原 Telegram Bot 消息中通过带归属检查的按钮决定。

## 测试

长期回归与临时验收边界见 [验证策略](../testing.md)。本模块其余行为在变更时针对性验收，不保留逐方法测试清单。
