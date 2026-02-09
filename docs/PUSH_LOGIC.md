# 内容推送逻辑详解

本文档详细说明了 VaultStream 的内容推送流程，包括自动调度、个性化渲染、多平台分发以及目标管理逻辑。

## 1. 核心组件

推送系统由以下几个核心组件组成：

*   **DistributionScheduler (backend/app/distribution/scheduler.py)**: 定时任务调度器，负责扫描 `scheduled_at` 符合条件的内容。
*   **DistributionEngine (backend/app/distribution/engine.py)**: 分发引擎，负责规则匹配、个性化模板渲染、去重检查及任务生成。
*   **TaskWorker (backend/app/worker)**: 后台 Worker 进程，消费分发任务。
*   **PushService (backend/app/push)**: 平台特定的推送实现。
    *   **TelegramPushService**: 支持 HTML/Markdown 渲染。
    *   **NapcatPushService**: 支持 QQ (OneBot 11) 协议，包含合并转发逻辑。

## 2. 推送流程

### 2.1 自动推送流程 (基于调度的时间线)

1.  **调度**: `DistributionScheduler` 每 60 秒运行一次。
2.  **选品**: 查询状态为 `PULLED` 且审核状态为 `APPROVED` 的内容。
    *   **核心逻辑**: 检查 `scheduled_at <= utcnow()`。
    *   **排序**: `queue_priority` 降序，其次 `scheduled_at` 升序。
3.  **规则匹配与渲染**:
    *   `DistributionEngine` 查找匹配规则。
    *   **个性化渲染**: 检查规则或目标（Target）是否定义了 `render_config`。如果有，则覆盖系统默认模板。
    *   **模板变量**: 支持 `{{date}}`, `{{title}}`, `{{author}}`, `{{url}}` 等占位符。
4.  **去重与过滤**:
    *   检查 `PushedRecord` 防止重复推送。
    *   NSFW 策略过滤。
5.  **分发执行**: 生成任务并异步调用各平台的 `PushService`。

### 2.2 队列标准化操作

*   **立即推送 (Push Now)**: 通过设置 `scheduled_at` 为过去 24 小时并将优先级设为最高 (9999)，强制内容在下一次轮询时立即发送。
*   **合并分组 (Merge Group)**: 将多个内容的 `scheduled_at` 对齐到同一时间点。分发引擎会识别同时间的任务，对于支持的平台（如 QQ）自动采用**合并转发 (Merged Forward)** 模式。

## 3. 个性化渲染 (Render Config)

系统支持对每个分发规则甚至每个具体目标配置不同的渲染风格。

### 3.1 内置预设模板 (Presets)

1.  **Minimal (精简)**: 仅包含标题和链接，适合高频转发。
2.  **Standard (标准)**: 包含标题、摘要和自动媒体展示。
3.  **Detailed (详细)**: 展示全部字段、页眉页脚及完整媒体。
4.  **Media-Only (纯图片/视频)**: 以媒体为核心，仅保留极简说明。

### 3.2 渲染优先级

1.  **Target Override**: 如果具体目标配置了 `render_config`，优先级最高。
2.  **Rule Config**: 否则使用规则定义的配置。
3.  **Global Default**: 最后回退到系统全局配置。

## 4. QQ 接入 (Napcat/OneBot 11)

VaultStream 通过 Napcat 接入 QQ 生态：

*   **连接方式**: 使用 HTTP API 协议连接。
*   **消息格式**: 采用 JSON Array 格式。
*   **性能优化**: 大量内容并发时，自动在规则/目标级别通过“合并转发”减少对频道的骚扰。

## 5. 目标管理 (Target Management)

独立管理页面允许用户跨规则查看所有活跃目标：

*   **连接测试**: 实时验证 Bot 是否能访问指定的 Telegram 频道或 QQ 群组。
*   **状态概览**: 显示每个目标的启用状态、总推送次数、最后推送时间以及关联的规则数量。
*   **批量更新**: 支持跨规则批量修改目标的启用状态或渲染模板。

---

## 6. 排查指南

1.  **检查 scheduled_at**: 确认内容是否已到达预定的推送时间。
2.  **验证连接**: 在“目标管理”页面对目标进行“连接测试”。
3.  **日志跟踪**: 
    *   `Updating targeted content rendering with config...`: 检查是否有配置覆盖。
    *   `Target connection test failed`: 目标配置可能过时或 ID 无效。
