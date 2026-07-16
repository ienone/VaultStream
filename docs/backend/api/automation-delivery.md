# API 领域：探索、同步与分发

## 文档状态

active

## 事实来源

- Router：`discovery.py`、`favorites_sync.py`、`distribution_queue.py`、`distribution_rules.py`、`targets.py`、Bot 相关 router
- Service/Task：对应的 discovery、favorites、distribution 与 bot 模块

## 发现源

- `/api/v1/discovery/sources` 管理来源配置；单个来源可测试、同步、修改和删除。
- `POST .../test` 是只读质量检查：不写内容、不推进 cursor、不更新成功同步时间。
- `POST .../sync` 调度真实同步并返回 `run_id`。任务不可用和来源类型未实现使用不同业务错误。
- `/api/v1/discovery/items` 与 `/stats` 描述当前发现缓冲区，不等同于未来动态信息流的最终产品模型。

## 收藏同步

- `GET /api/v1/favorites-sync/status` 返回平台状态和当前策略。
- `POST /api/v1/favorites-sync/preview` 只预估，不推进同步 cursor。
- `POST /api/v1/favorites-sync/sync` 创建可观察运行。
- 单条和批量失败重试只重新处理指定候选，不重新拉取整个收藏夹。

当前重复策略支持合并或跳过本地已有规范链接；远端取消收藏不会自动删除本地存档。运行结果可包含平台汇总和截断后的失败样本。

## 分发队列

- 队列项以具体内容、规则和目标组合为操作边界。
- `/api/v1/distribution-queue/items` 提供状态、内容、规则、目标和分页筛选。
- 单条队列项的 retry、cancel、push-now、schedule、status 和 reorder 只影响该目标。
- `content/{content_id}` 系列接口会影响同一内容关联的多个目标，只能在用户明确选择内容维度操作时使用。

立即排期和外部推送成功是两个不同阶段。调度接口返回的 `run_id` 不能被解释为消息已经送达。

## 规则与目标

- `/api/v1/distribution-rules` 管理匹配与渲染规则。
- 规则和目标关联由 `/distribution-rules/{rule_id}/targets` 单独维护。
- 历史回填支持仅新内容、最近若干天和全部历史；preview 只返回候选数量，不创建目标或队列项。
- `/api/v1/targets` 是跨规则目标视图，平台口径统一为 `telegram` 或 `qq`。
- 连接测试不发送消息；`send-test` 才会发送固定诊断消息，且不计入正常内容推送记录。

## Bot 配置与会话

- BotConfig 表示账号/连接配置，BotChat 表示运行时发现的群组、频道或会话。
- 创建或 upsert BotChat 必须明确 `bot_config_id`。
- Telegram 会话同步使用启用且为主配置的 BotConfig，并返回运行结果。
- QR code 当前是普通 HTTP 查询，不是 WebSocket 流。

## 变更检查

- 写操作必须区分预览、调度、执行和最终成功。
- 批量接口要有数量上限、逐项结果和可观察 run。
- 外部副作用必须经过用户可见策略和权限边界。
