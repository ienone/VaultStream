# 后端模块：事件与后台任务

## 文档状态

active

## 代码位置

- Events: `backend/app/core/events.py`、`backend/app/routers/events.py`
- Task state: `backend/app/services/background_task_state.py`
- Diagnostics service: `backend/app/services/system_diagnostics_service.py`
- Run ledger: `backend/app/models/system.py::BackgroundTaskRun`
- Migrations: `backend/migrations/versions/`
- Tasks: `backend/app/tasks/*`
- Queue adapter: `backend/app/core/queue_adapter.py`

## 功能

- SSE 事件订阅；无业务事件时每 30 秒发送心跳，早于前端 90 秒失活阈值。
- 后台任务 run 状态记录。
- 任务指标、诊断和失败详情。
- 解析、发现、分发、收藏同步和周期摘要等任务执行。

## 不承担职责

- 不决定具体业务任务是否允许执行。
- 不替代业务 service 的失败处理。
- 不在前端重复定义任务详情格式。

## 实现逻辑

每一次可观察运行只写入 `background_task_runs`，以全局唯一 `run_id` 作为稳定身份。任务汇总状态、最近成功/失败时间及计数从保留的运行记录查询生成，不再单独写入 `SystemSetting`；计数表示保留历史，不是终身累计。开始、成功和失败通过 SQLite upsert 原子结算，同一任务保留最近 200 条终态，以及所有非终态、当前写入和仍被持久消息引用的运行；消息记录存在期间 run 不被数量清理删除。收藏同步还保留每个平台的最近结果所属运行，避免其他平台的频繁同步清掉其状态。诊断接口跨任务按开始时间查询该表，不依赖任务名白名单；详情接口按主键直接读取。

任务落盘后通过 event bus 提示前端刷新；事件 payload 不是事实源。运行账本与 SSE 持久事件表由数据库初始化入口创建，后续变更使用 Alembic 增量迁移；已移除旧 JSON 列表回填和 event bus 自行建表逻辑。

终态 run 会交给消息盒子判断是否值得通知：所有失败进入消息盒子，只有用户主动触发的成功产生完成回执。消息写入失败只记录告警，不回滚已经正确结算的运行账本。消息去重与用户状态见 `notification-inbox.md`。

`NotificationDigestTask` 只在 leader 中运行并周期检查用户配置；到期时调用确定性的摘要 service，结果写入同一任务汇总状态。禁用或未到期时不创建 run 或消息，空窗口只推进摘要游标。

读取 run 时，后端按真实 task type 生成只读 `presentation` 投影，不把展示字段重复写入账本。投影稳定包含业务标题、摘要、可识别错误码、实体链接、安全导航动作和结果 section；原始 `metadata/result` 继续保留为诊断事实。收藏同步、内容处理、语义索引、发现、分发、平台/AI 连通性与 Bot 群组同步已有专用映射，未知任务只给通用标题和状态，不猜测业务动作。后台失败详情、run 查询、provider 状态和 Prometheus 文本由 `SystemDiagnosticsService` 统一构造，system router 不再直接聚合任务账本。

Bot 进程控制和 chat 同步已经离开 API router 并进入可注入 service。配置保存触发的进程同步、手动 start/stop/restart、手动 chat sync 与 QQ 自动同步均写入统一 run 账本；`bot_sync_progress` / `bot_sync_completed` 事件仍只用于即时提示，持久 run 才是任务结果事实源。手动成功与所有失败继续复用统一消息盒子投影。

解析队列每行只执行一次：PENDING → RUNNING → COMPLETED/FAILED，不再使用租约重领、世代或重复执行预算。30 分钟是执行超时；轮询发现超时 RUNNING 时结算失败，不重新抓取。写入结果仍要求该任务行处于 RUNNING，避免已结束任务的迟到结果提交。解析事实与 Task 完成同事务写入。

队列和手动重新解析共用 `ContentParser.execute_parse`，每次调用适配器一次，保留 force 与人工候选语义。摘要、索引和审批在解析提交后执行，其失败不降级已保存正文。运行账本直接更新状态和结果，不把展示字典及序列化时间再解析回数据库；元数据保留在原记录中。

`TaskWorker` 在每次从解析队列领取任务前通过 `AutomationPolicyService` 读取持久化的 `enable_parse_worker`。关闭时 worker 保持存活但不调用 dequeue，既有 pending 任务原样等待；内容捕获和入队不受影响，重新开启后继续领取。该策略不抢占或中断已经进入执行中的解析任务。

## 测试

长期回归与临时验收边界见 [验证策略](../testing.md)。本模块其余行为在变更时针对性验收，不保留逐方法测试清单。

## 与其他模块交互

- contents、discovery、distribution、favorites-sync、search-rag 都会写入任务状态。
- frontend task result 页面读取 run 详情。

## 对应前端

- `../../frontend/pages/dashboard.md`
- `../../frontend/pages/tasks.md`
- `../../frontend/components/task-result.md`

## API 接口

- `GET /api/v1/events/subscribe`
- `GET /api/v1/events/health`
- `GET /api/v1/background-tasks/diagnostics`
- `GET /api/v1/background-tasks/runs/{run_id}`
- `GET /api/v1/background-tasks/metrics`

## 配置与策略

- 后台任务执行前应读取对应业务策略。
- 解析 worker 的暂停策略在每次 dequeue 前动态读取；关闭只暂停消费，不改变捕获、入队或既有任务状态。
- run 核心字段为 `run_id`、`task`、`status`、开始/结束时间、`error`、`metadata` 和 `result`。
- 服务内部仍以展开字典使用任务 metadata；通用 API 只在明确的 `metadata` 对象内输出任务特定字段。
- 运行账本不是可执行队列；不能从 run 账本推断或自动重跑工作。run 中进程崩溃遗留的 `running` 记录自身仍不自动结算。
- `presentation.allowed_actions` 当前只表达可安全导航的产品入口。不同任务的真实重试参数和权限仍由领域 API 决定；收藏同步失败项由任务页专用 renderer 调用现有 retry contract，不由通用任务页拼接 endpoint。

## 尚未实现 / 计划扩展

核心 run contract 与常用 task renderer 已稳定。后处理尚非耐久工作流；不能仅为推测中的恢复需求引入租约或自动重放。


## 2026-09-06 职责收敛

任务与通知统一使用 `task_run_presentation` 的标题、结果摘要和终态集合。任务结果先显示摘要和有意义的指标；全零同步指标不重复成四个格子，run ID、触发来源与错误码放在诊断区。

`BackgroundTaskRun` 负责一次执行的持久状态、关联和结果。`background_task_state:*` 只保留真实常驻 worker 的运行健康快照，不能当作某次执行结果；逐内容 embedding 没有独立 worker，已移除其重复投影写入，只保留对应 `content_embedding` 运行记录。

## 实时界面更新

任务首次落盘及终态提交后发布 `background_task_updated`，携带 `task/status/run_id`；任务 metadata 有 `content_id` 时一并提供。事件只提示重读持久事实，重复结算不重复广播。解析进入 processing、解析正文提交时分别发布 `content_updated`，正文显示不等待摘要与索引结束。

前端在连接确认和 App 回到前台重连后补读可见资源；切换服务器或账号清除旧事件游标。收藏、正文、处理阶段、任务结果、消息盒子和收藏同步状态订阅各自事件，短时间事件合并读取，收藏保留已加载页数。移除 Web 专属的固定频率任务/消息轮询。

每一层反向代理都必须关闭 SSE 缓冲。容器 Nginx 对 `/api/v1/events` 关闭缓冲，并向外层保留 `X-Accel-Buffering: no`。生产外层 Nginx 的 `/api/v1/events/` 同样设置 `proxy_http_version 1.1`、`proxy_set_header Connection '';`、`proxy_buffering off`、`proxy_cache off`、`proxy_read_timeout 86400s`，目标沿用现有 Web 容器。核验必须经过用户实际访问的域名，API 直连成功不能证明整条代理链及时送达。
