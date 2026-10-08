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
- platforms 使用命名 `FavoritesPlatformStatusResponse`，capabilities 明确 supported/scope/pagination/collection_metadata/authentication/limitation。未接入的平台仍返回能力说明，但 available=false，不能启用或执行。当前可执行平台注册为知乎、小红书、Bilibili、微博、X；X 需要服务端浏览器及显式保存的网页登录；未知/未接入平台的执行请求明确失败。
- `POST /api/v1/favorites-sync/preview` 只预估，不推进同步 cursor。
- `POST /api/v1/favorites-sync/sync` 创建可观察运行。
- 单条和批量失败重试只重新处理指定候选，不重新拉取整个收藏夹。
- trigger/run retry 的 `202 accepted` 以及单条/批量 retry 的完成统计分别使用命名响应；`run_id` 均为必需字段，不能由调用方按“可能存在”处理。

当前重复策略支持合并或跳过本地已有规范链接；远端取消收藏不会自动删除本地存档。运行结果可包含平台汇总和截断后的失败样本。

## 分发队列

- 自动队列以内容、规则和目标组合为操作边界；手动项 `rule_id=null`，按内容与 BotChat 唯一。统计按队列项计数，与列表一致。
- `/api/v1/distribution-queue/items` 提供状态、内容、规则、目标、卡片用途的有序 `media_assets` 和分页筛选；签名媒体 URL 跟随当前请求 origin。
- 单条队列项的 retry、cancel、push-now、schedule、status 和 reorder 只影响该目标。
- `content/{content_id}` 系列接口会影响同一内容关联的多个目标，只能在用户明确选择内容维度操作时使用。
- 过去由 inline dict 表达的 enqueue/cancel/batch retry，以及内容级 push/schedule/reorder/status/repush 现均有命名响应；`changed/moved/retried_count` 是同步完成的数量，只有明确返回的 `run_id` 才可跳转任务详情。

立即排期和外部推送成功是两个不同阶段。调度接口返回的 `run_id` 不能被解释为消息已经送达。

发送未知结果沿用 `status=failed`，以 `reason_code/last_error_type=delivery_unknown` 明确标识，并提供带时区的 `last_error_at`。未知记录属于 `filtered` 列表，普通重试、取消、批量排期/重推不能修改它。单项 push-now 是同步执行路径，调用方必须读取返回资源状态，不能无论结果如何都提示“已加入队列”。

发送回执缺失只在队列记录，不产生人工核对任务或填写消息 ID 的流程；已删除 reconcile 接口和 review_item 深链。保留发送中及未知结果的自动重发保护。

## 规则与目标

- `/api/v1/distribution-rules` 管理匹配与渲染规则。
- 创建／更新规则支持可选 `bot_chat_ids`（1–50 个），提供时原子保存完整目标集合；新增目标水位为绑定时刻。无效目标返回 409 且不保留部分规则修改。独立目标接口继续服务既有 API 调用方。
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

聚合复用 `PUT /settings/{key}`：`enable_content_aggregation`、`enable_aggregation_push` 均为 boolean，默认 false，category=automation。状态与产物 ID 复用 background task diagnostics 的 `content_aggregation` 运行记录；不新增平行调用接口。内部 `content_aggregation_cursor`、`content_aggregation_last_attempt` 为恢复进度，不是用户配置项。

队列状态变更（重试、取消、状态切换、排期、重推）使用条件更新保护正在发送的租约；任务已 processing 或读取后状态变化返回 HTTP 409，调用方应刷新列表。批量请求遇到此冲突整批事务回滚，不返回部分成功数量。

收藏单项/批量重试条目支持可选 collection_id、collection_title，调用方从失败项原样传回；重试复用正常同步的来源身份。已存在且处理完成的单项重试返回既有 content_id 与新的 run_id，不重复创建来源。

Bot 心跳请求必须携带 `bot_config_id`，后端核验配置平台、启用状态和 Telegram Bot 身份。`/bot/status` 与 `/bot/runtime` 仅展示当前主配置的心跳；更换 token 会撤销旧运行状态。发现来源筛选使用全部来源关联，响应不再返回单个 `discovery_source_id`。

## Telegram 用户账号同步

- GET `/api/v1/telegram-account/status` → TelegramAccountStatus：configured、session_present、running、channels_enabled、saved_enabled；session_present 仅指本地会话文件存在。
- PUT `/api/v1/telegram-account/options`，请求／响应 TelegramSyncOptions：channels_enabled、saved_enabled 两个必填布尔值。
- POST `/api/v1/telegram-account/sync` → 202 TelegramSyncAccepted（run_id）。关闭、未配置或已有同步时为 409；非 leader 进程为 503。
- 三个接口均沿用 API Token 鉴权。任务记录名 telegram_account_sync，结果含 channels、created、updated、saved 数量。

Telegram options 写入同样要求 leader（否则 503）；关闭任一同步项时，响应前等待运行中批次取消，避免旧配置继续执行。

### Telegram 显式登录

- POST `/api/v1/telegram-account/login` → 202 TelegramLoginStatus，缺应用凭据或同步／登录占用时 409。
- GET `/api/v1/telegram-account/login/{login_id}` → TelegramLoginStatus，不存在或已被新登录替换时 404。
- POST `/api/v1/telegram-account/login/{login_id}/password` 接受 `{password: string}` → TelegramLoginStatus；当前不需要密码时 409。
- DELETE `/api/v1/telegram-account/login/{login_id}` → TelegramLoginStatus，等待连接退出；不会登出已完成的授权会话。
- TelegramLoginStatus：login_id、state（waiting/qr/password_required/authorized/expired/failed/cancelled）、qrcode_b64、expires_at、message。只有 qr 状态提供二维码，终态清空二维码。所有请求要求 API Token 和当前 leader；其他进程 503。登录最长五分钟，二维码自身到期后不自动重发。

## 手动选择内容推送

`POST /distribution-queue/manual` 接受 `content_ids`（1–50）、`bot_chat_ids`（1–10），最多 100 个组合，拒绝额外字段。目标必须启用、可访问、允许推送且属于启用的主 Bot；内容必须解析完成且未删除，聚合外发策略继续生效。无效内容、目标、已有发送中或未知结果返回 409，事务回滚。

200 返回 `ManualPushResponse {item_ids, already_sent}`，只准备手动队列，不声明送达。手动项使用 `approved_by=manual`，不改变内容全局审批或收藏状态；客户端逐项调用现有 `/items/{id}/push-now`，读取实际 status。重复准备复用同一项，已送达组合只计入 already_sent。失败仍在正式队列中处理；未收到发送回执的记录保留，阻止自动重复发送。

规则要求人工确认时，匹配的新内容进入 `failed/approval_required`、无自动重试；逐项立即发送或显式排期只确认该队列项。删除规则或移除目标时若存在 processing／delivery_unknown，返回 409。保存规则不再隐式扫描全部历史内容。

队列列表与统计不再把已有成功发送记录的同内容、同平台、同目标的其他旧排期算作待发送；发送中和未收到发送回执的条目仍保留，不能被成功记录遮蔽。单项接口与数据库记录保持可追溯。

已发送队列（`status=pushed` / `success`）按完成时间、ID 倒序分页；待发送队列继续按计划时间、ID 正序。
