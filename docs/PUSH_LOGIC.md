# 内容推送逻辑详解

本文档详细说明了 VaultStream 的内容推送流程，包括自动调度、手动重推、去重逻辑以及 Bot 的交互流程。

## 1. 核心组件

推送系统由以下几个核心组件组成：

*   **DistributionScheduler (backend/app/distribution/scheduler.py)**: 定时任务调度器，负责定期扫描待推送的内容。
*   **DistributionEngine (backend/app/distribution/engine.py)**: 分发引擎，负责规则匹配、去重检查、NSFW 策略检查，并生成分发任务。
*   **TaskQueue (Redis/SQLite)**: 任务队列，用于存储待执行的分发任务。
*   **TaskWorker (backend/app/worker)**: 后台 Worker 进程，负责从队列消费任务。
*   **ContentDistributor (backend/app/worker/distributor.py)**: 执行具体的分发逻辑（调用 Bot API）。
*   **PushService (backend/app/push)**: 平台特定的推送实现（如 TelegramPushService）。

## 2. 推送流程

### 2.1 自动推送流程

1.  **调度**: `DistributionScheduler` 每 60 秒运行一次 `_check_and_distribute`。
2.  **选品**: 查询数据库中状态为 `PULLED` 且审核状态为 `APPROVED` 或 `AUTO_APPROVED` 的内容。
    *   **排序**: 优先按 `queue_priority` 降序（高优先级先推），其次按 `created_at` 升序（旧内容先推）。
    *   **限制**: 每次最多选取 50 条。
3.  **规则匹配**: `DistributionEngine` 遍历内容，查找匹配的 `DistributionRule`。
    *   匹配条件包括：标签、平台、NSFW 属性。
4.  **过滤与检查**:
    *   **NSFW 策略**: 检查规则的 NSFW 设置（Block/Allow）。
    *   **去重**: 检查是否已推送到目标（`PushedRecord`）。
    *   **频率限制**: 检查目标是否达到推送速率限制。
5.  **任务生成**: 如果检查通过，生成 `distribute` 类型的任务并推入 `TaskQueue`。
6.  **执行**: `TaskWorker` 获取任务，调用 `ContentDistributor`。
7.  **推送**: `ContentDistributor` 调用 `TelegramPushService` 发送消息。
8.  **记录**: 成功后写入 `PushedRecord`，失败则记录错误。

### 2.2 手动重推流程 (Repush)

当用户在前端点击“重推”按钮时：

1.  **前端请求**: 发送 POST 请求到 `/api/v1/queue/items/{id}/move`，状态设为 `will_push`。
2.  **状态重置 (Queue Router)**:
    *   后端将内容的 `review_status` 更新为 `APPROVED`。
    *   **关键**: 将 `reviewed_at` 更新为当前时间。
    *   **关键**: 将 `status` 重置为 `PULLED`（确保调度器能再次扫描到）。
3.  **调度**: `DistributionScheduler` 在下一次循环（或手动触发）时扫描到该内容。
4.  **智能去重 (Engine)**:
    *   `DistributionEngine` 检测到存在旧的 `PushedRecord`。
    *   但是，它会比较 `content.reviewed_at` 和 `record.pushed_at`。
    *   如果 `reviewed_at > pushed_at`（即重新审核时间晚于上次推送），则**允许**再次推送。
5.  **执行**: 任务正常生成并执行，生成新的 `PushedRecord`。

## 3. Bot 连接与心跳

*   Bot 作为一个独立的进程（或线程）运行。
*   它通过 `HTTP_PROXY` 环境变量连接 Telegram 服务器。
*   它定期向后端 API 发送心跳 (`/bot/heartbeat`) 以报告在线状态。
*   如果 Bot 日志显示 `Timed out` 或 `RemoteProtocolError`，通常意味着代理配置不正确或网络不稳定，导致无法连接 Telegram 服务器。

## 4. 排查指南

如果遇到“不推送”的情况，请按以下步骤排查：

1.  **检查内容状态**: 确保内容在“待推送”列表中（即 `review_status=APPROVED`, `status=PULLED`）。
2.  **检查规则**: 确保有启用的分发规则能匹配该内容（标签、平台）。
3.  **检查日志**:
    *   搜索 `分发调度器: 找到 X 条候选内容`。
    *   搜索 `内容无匹配规则` 或 `NSFW策略阻止` 或 `内容已推送到目标`。
    *   搜索 `已创建分发任务`。
4.  **检查 Bot**:
    *   查看 Bot 进程日志，确认没有连接错误。
    *   确认 Bot 已加入目标频道并有发言权限。

## 5. 常见问题

*   **Q: 为什么点了重推还是没反应？**
    *   A: 可能是去重逻辑误判。请检查后端日志中是否有 `内容已推送到目标` 的 Warning。最新版本已修复此逻辑，依据 `reviewed_at` 判断。
*   **Q: Bot 心跳超时怎么办？**
    *   A: 检查 `.env` 文件中的 `HTTP_PROXY` 配置是否正确，例如 `http://127.0.0.1:7890`。
