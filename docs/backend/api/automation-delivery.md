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
- source test、source sync、source delete 和候选 bulk action 使用各自命名 response model；test 的 `run_id/status/ok/elapsed_ms` 与样本统计属于稳定 contract。
- `/api/v1/discovery/items` 是当前动态信息流的读取契约：列表条目包含来源正文预览、全部关联来源名称和类型、候选状态，以及卡片用途的有序 `media_assets`；它不把来源正文声明为 AI 摘要。单项读取与动作响应返回详情用途的资产。
- `PATCH /api/v1/discovery/items/{item_id}` 接受 `promoted`、`ignored`、`snoozed` 和 `visible`；`snoozed` 从默认流移入稍后列表，`GET /discovery/items?state=snoozed` 读取该持久状态，`visible` 把条目恢复到默认流。`/stats` 仍只是发现缓冲区统计，不作为动态流内容模型。

## 收藏同步

- `GET /api/v1/favorites-sync/status` 返回平台状态和当前策略。
- `POST /api/v1/favorites-sync/preview` 只预估，不推进同步 cursor。
- `POST /api/v1/favorites-sync/sync` 创建可观察运行。
- 单条和批量失败重试只重新处理指定候选，不重新拉取整个收藏夹。
- trigger/run retry 的 `202 accepted` 以及单条/批量 retry 的完成统计分别使用命名响应；`run_id` 均为必需字段，不能由调用方按“可能存在”处理。

当前重复策略支持合并或跳过本地已有规范链接；远端取消收藏不会自动删除本地存档。运行结果可包含平台汇总和截断后的失败样本。

## 分发队列

- 队列项以具体内容、规则和目标组合为操作边界。
- `/api/v1/distribution-queue/items` 提供状态、内容、规则、目标、卡片用途的有序 `media_assets` 和分页筛选；签名媒体 URL 跟随当前请求 origin。
- 单条队列项的 retry、cancel、push-now、schedule、status 和 reorder 只影响该目标。
- `content/{content_id}` 系列接口会影响同一内容关联的多个目标，只能在用户明确选择内容维度操作时使用。
- 过去由 inline dict 表达的 enqueue/cancel/batch retry，以及内容级 push/schedule/reorder/status/repush 现均有命名响应；`changed/moved/retried_count` 是同步完成的数量，只有明确返回的 `run_id` 才可跳转任务详情。

立即排期和外部推送成功是两个不同阶段。调度接口返回的 `run_id` 不能被解释为消息已经送达。

## 规则与目标

- `/api/v1/distribution-rules` 管理匹配与渲染规则。
- 规则和目标关联由 `/distribution-rules/{rule_id}/targets` 单独维护。
- 规则删除和人工分发扫描返回各自命名结果；规则目标删除使用 bodyless `204`，调用方不得等待 JSON。
- 历史回填支持仅新内容、最近若干天和全部历史；preview 只返回候选数量，不创建目标或队列项。
- `/api/v1/targets` 是跨规则目标视图，平台口径统一为 `telegram` 或 `qq`。
- 连接测试不发送消息；`send-test` 才会发送固定诊断消息，且不计入正常内容推送记录。

## Bot 配置与会话

- BotConfig 表示账号/连接配置，BotChat 表示运行时发现的群组、频道或会话。
- 创建或 upsert BotChat 必须明确 `bot_config_id`。
- Telegram 会话同步使用启用且为主配置的 BotConfig，并返回运行结果。
- BotChat 删除、启停切换和 heartbeat 使用独立命名响应；heartbeat 只确认本次状态写入，不代表 Bot 进程整体健康。
- Telegram 服务 start/stop/restart 使用 `BotRuntimeActionResponse`，返回真实进程状态和稳定 `run_id`；restart 任一内部阶段失败时整体状态为 error。手动群组同步返回 `BotConfigSyncChatsResponse.run_id`，QQ 配置自动同步会在响应前先创建 run 再交给后台执行。Bot 配置 create/update/activate 返回 `BotConfigMutationResponse`，delete 返回 `BotConfigDeleteResponse`，均直接携带后续运行的 kind、run ID、状态和错误；配置已提交但运行时失败时仍明确返回配置事实，不伪装成事务回滚。
- Telegram `/save` 是用户显式捕获入口：链接逐项调用 `/api/v1/shares`，纯文本调用 `/api/v1/captures/text`，图片、文件、音视频与语音下载后作为 multipart 调用 `/api/v1/captures/files`。私聊里严格匹配“帮我保存 …”“收藏：…”等明确前缀的文本也进入同一个 `save_command`，不另建写路径。三类入口统一写入 `Content`、`ContentSource(source=telegram_bot)`；链接进入正式解析队列，原始文本和附件使用各自既有后处理。回复消息时只保存必要的 chat/message/forwarded/media group/attachment type 上下文。
- 显式捕获不复用 `handle_monitored_message`。文本路由只在私聊且严格命中保存前缀时截获，否则继续交给原监控处理器；后者仍只负责已启用 chat 的发现缓冲，两条路径的用户意图和内容状态不同。
- 当前一次请求只处理一条消息中的一个附件；跨消息 media group 合并、开放式自然语言判断和不确定场景确认尚未接入 Bot 捕获。
- QR code 当前是普通 HTTP 查询，不是 WebSocket 流。

## 变更检查

- 写操作必须区分预览、调度、执行和最终成功。
- 批量接口要有数量上限、逐项结果和可观察 run。
- 外部副作用必须经过用户可见策略和权限边界。
