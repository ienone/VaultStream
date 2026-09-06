# 自动化模块说明

## 概述
`frontend/lib/features/automation/` 是当前 `/automation` 页面实现目录，权威页面职责以 `docs/frontend/pages/automation.md` 为准。

本目录不维护独立产品口径；后续自动化三域化时，应在当前自动化目录内继续拆分概览、收藏同步、分发、解析/后处理等边界，而不是恢复旧审核页面语义。

## 当前能力
1.  内容队列管理 (Content Queue):
    *   查看不同状态的内容（待推送、不推送、待审批、已推送）。
    *   支持审批流操作（通过/拒绝/重置内容状态）。
    *   在“待推送”队列中支持拖拽排序，手动调整发布顺序。
2.  分发规则配置 (Distribution Rules):
    *   多维度规则定义：基于标签过滤、NSFW 策略、发布频率限制等。
    *   规则级预览：支持按特定规则筛选查看受影响的内容。
3.  收藏同步与处理链:
    *   展示收藏同步策略、最近运行和失败重试。
    *   按解析、媒体归档、内容理解和索引展示真实策略与运行状态。
4.  推送历史:
    *   记录所有已尝试的推送任务，支持失败重试操作。

## 目录结构

### 核心文件
*   `automation_page.dart`: 模块主入口，实现总览与三个领域分区。
*   `distribution_rule_page.dart`: 可刷新、可返回的复杂规则新建与编辑页面。

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
*   `rule_list_tile.dart`: 规则选择行，保留启用开关、审批状态和查看/编辑菜单。
*   `distribution_rule_editor.dart`: 规则页面复用的响应式编辑面。
*   `pushed_record_tile.dart`: 推送历史条目。

## 设计规范
*   UI 风格: 严格遵循 Material 3 Expressive 设计规范。
*   响应式: 使用统一 WindowMetrics 与实际内容宽度；短横屏压缩队列控制区，保留可滚动正文。
*   交互: 动画只服务于状态切换；领域入口与规则选择不套多层卡片。

## API 依赖
主要交互后端 `/distribution-queue/*`、`/distribution-rules/*`、`/distribution-rules/{rule_id}/targets/*`、`/favorites-sync/*`、`/background-tasks/diagnostics` 和 `/search/semantic/index-status`。
