# Review & Distribution 模块

## 概述
`review` 模块是 VaultStream 前端的核心功能之一，主要负责 内容审批、分发规则管理、Bot 群组配置 以及 推送历史追踪。为用户提供了一个集中的面板来控制已存档内容自动分发的流程。

## 核心功能
1.  内容队列管理 (Content Queue):
    *   查看不同状态的内容（待推送、不推送、待审批、已推送）。
    *   支持审批流操作（通过/拒绝/重置内容状态）。
    *   在“待推送”队列中支持拖拽排序，手动调整发布顺序。
2.  分发规则配置 (Distribution Rules):
    *   多维度规则定义：基于标签过滤、NSFW 策略、发布频率限制等。
    *   规则级预览：支持按特定规则筛选查看受影响的内容。
3.  Bot & 渠道管理:
    *   管理 Telegram Bot 及其关联的群组/频道。
    *   支持手动同步后端 Bot 状态和触发即时分发任务。
4.  推送历史:
    *   记录所有已尝试的推送任务，支持失败重试操作。

## 目录结构

### 核心文件
*   `review_page.dart`: 模块主入口，实现了响应式的 Master-Detail 布局（宽屏显示侧边栏规则，窄屏显示折叠面板）。

### `models/` (数据模型)
*   `queue_item.dart`: 队列中的内容条目，包含平台、作者、调度时间等信息。
*   `distribution_rule.dart`: 分发规则模型。
*   `bot_chat.dart`: Bot 关联的群组/频道信息。
*   `pushed_record.dart`: 推送历史记录。

### `providers/` (状态管理)
*   `queue_provider.dart`: 管理内容队列的获取、筛选、排序及状态移动。
*   `distribution_rules_provider.dart`: 管理分发规则的 CRUD 状态。
*   `bot_chats_provider.dart`: 处理 Bot 群组的同步与管理。
*   `pushed_records_provider.dart`: 管理推送历史列表。

### `widgets/` (UI 组件)
*   `queue_content_list.dart`: 内容队列列表容器，包含拖拽排序逻辑。
*   `rule_list_tile.dart`: 规则列表项，支持展开查看详情及快捷操作。
*   `rule_config_panel.dart`: 规则配置的详细展示面板。
*   `bot_chat_card.dart` / `bot_status_card.dart`: Bot 相关信息的展示组件。
*   `distribution_rule_dialog.dart` / `bot_chat_dialog.dart`: 用于创建和编辑配置的弹出对话框。
*   `pushed_record_tile.dart`: 推送历史条目。

## 设计规范
*   UI 风格: 严格遵循 Material 3 Expressive 设计规范。
*   响应式: 针对平板/桌面端（宽度 > 800dp）和手机端做了差异化布局优化。
*   交互: 大量使用动画切换（如 `AnimatedSize`, `AnimatedCrossFade`）以提升用户体验。

## API 依赖
主要交互后端 `/distribution-queue/*`, `/distribution-rules/*`、`/distribution-rules/{rule_id}/targets/*` 以及 `/bot/*` 系列接口。
