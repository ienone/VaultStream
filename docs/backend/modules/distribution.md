# 后端模块：分发系统

## 文档状态

active

## 代码位置

- Router: `backend/app/routers/distribution.py`
- Queue router: `backend/app/routers/distribution_queue.py`
- Service: `backend/app/services/distribution/service.py`
- Enqueue helpers: `backend/app/services/distribution/scheduler.py`
- Rule service: `backend/app/services/distribution_rule_service.py`
- Push: `backend/app/push/*`
- Tasks: `backend/app/tasks/distribution_worker.py`

## 功能

- 管理分发规则和目标。
- 根据内容匹配规则生成队列项。
- 支持推送、取消、重试、重新排序、批量操作。
- 支持 Telegram 和 Napcat/QQ 推送服务。

## 不承担职责

- 不管理平台账号登录。
- 不解析原始内容。
- 不替代收藏库内容编辑。

## 实现逻辑

内容入库或规则刷新后，`DistributionService` 根据条件匹配规则，生成 `content_queue_items`。`enqueue_content_background` 只负责创建/关闭独立 session 和记录后台异常；旧空 `DistributionEngine` 别名与测试透传函数已删除。worker 消费队列并调用 push service，将结果记录到 pushed records。

队列列表和单项响应批量/按项附带卡片用途的统一 `media_assets`，签名 URL 使用当前请求 origin。前端队列预览不再自行猜测或改写封面 URL。worker 推送前会连同变体一次性加载媒体资产；`ContentDistributor` 按 Telegram/QQ 能力选择本地可上传变体，并只把后端明确允许直连的远端原址作为兜底。Telegram 与 NapCat push service 只消费该 `media_items`，不再读取旧 archive metadata 或 `cover_url`；QQ 音频映射为 OneBot record 段。

分发队列的 enqueue、cancel、batch retry、push/schedule/reorder/status/repush，以及规则删除与人工扫描动作已从匿名响应收敛为命名 response model，并纳入 OpenAPI schema gate。数量字段表达当前请求已完成的数据库状态变更；`run_id` 仅在确实创建后台运行时出现。规则目标删除保持 `204 No Content`，同样由门禁固定。

仓库实验数据库已通过“真实队列/资产/本地 storage → worker → Telegram 适配器 → 队列与 pushed record 持久化”探针；网络边界由只记录上传字节的 Bot 替身截断，确认没有外部请求。真实 Telegram/QQ 账号发送与平台接受的媒体规格仍需在用户授权配置下验收，不能由本地探针外推。

## 测试

长期回归与临时验收边界见 [验证策略](../testing.md)。本模块其余行为在变更时针对性验收，不保留逐方法测试清单。

## 与其他模块交互

- contents: 内容状态和媒体用于推送。
- media: 推送时读取缩略图/媒体。
- config-system: 自动审批、worker 开关和策略应受配置控制。
- events-tasks: 推送结果进入事件和 run 记录。

## 对应前端

- `../../frontend/pages/automation.md`
- `../../frontend/pages/content-detail.md`

## API 接口

详见 `../api.md` 中分发队列 API、分发规则 API 和分发目标 API。

## 配置与策略

- `distribution_mode=paused` 会阻止自动审批、规则刷新产生的新自动审批、enqueue、队列 worker 和 Agent 批量推送；规则刷新仍可把已失效的 `AUTO_APPROVED` 安全降回 `PENDING`。
- 人工审核仍是显式用户操作，不因暂停自动分发而被隐藏；重新启用后，后续规则刷新或新内容处理可以继续自动审批。
- 分发目标和规则必须通过后端校验，不能只依赖前端禁用按钮。

## 历史决策

- [已关闭问题的历史决策](../../issues/archive/README.md)。

## 尚未实现 / 计划扩展

分发规则、目标、队列和运行结果的目标边界见前端 IA；选择该功能切片时，再基于当前 API、策略和 issue 确定实施范围。

自动聚合稿另受 `enable_aggregation_push` 控制，默认关闭且 force enqueue 不能绕过；worker 在构建 payload 后、实际发送前重读。自动审批仅处理 pending 的未删除内容，不覆盖人工拒绝。Agent 不重置 processing 队列项，并按读取状态条件更新，避免覆盖 worker 并发领取。

## 发送期间的策略变化

手动立即发送与自动领取都用状态条件更新，且同内容、同平台、同目标只能有一个处理中队列项。已有成功发送记录按平台及目标去重。渲染结束、实际发送前重新检查规则/目标启用、内容资格、规则匹配、人工审核、聚合推送与自动暂停；手动发送保留原有显式绕过自动暂停的语义。目标路由变化会暂缓并提示刷新队列，不能沿旧目标身份直接发送到新目标。已发起的网络请求不承诺能被稍后的开关撤回。

队列 API 的单项和批量状态变更同样与 worker 领取串行；不能通过重试、取消或重推清除活跃发送锁。并发变化返回 409 并回滚整个请求。

## 中断恢复与人工核对

每次领取使用独立 UUID 与 10 分钟锁时间；worker 每次只领取能马上执行的一项。候选查询与条件领取都要求规则和对应目标关联仍启用，停用项不占领取名额，重新启用后可继续原排期；发送前仍重新核对策略。现有 `last_error_type` 存储 `delivery_preparing` / `delivery_sending` 发送阶段，结果写入同时校验状态、锁时间、token 和有效期，不新增持久化枚举或数据库列。构建完成后先提交 sending 标记，再调用平台；网络等待期间不占用 SQLite 写锁。

到期 preparing 表示尚未调用发送服务，转为可有界重试的失败；达到尝试上限停止自动重试。显式人工重新排期仍可给予一次执行机会，不隐式清除历史尝试次数。到期 sending、缺少阶段信息的历史 processing，以及发送边界后的异常/空回执进入 `failed + delivery_unknown`，不自动重放。同内容、平台、目标的其他规则项也不能绕过未知结果发送，但不阻塞无关目标。暂停时继续归类遗留状态，不产生新的自动发送。

未知结果与消息盒子的逐条核对入口在同一事务持久化。`delivery_state.reconcile_delivery` 接受新鲜的人工观察，确认已送达需消息 ID，并原子写成功记录、目标统计和关闭通知；确认未发送保留失败状态、清除自动重试时间，并在同一事务里把当前同内容、平台、目标的其他已排期或待自动重试项转为 `failed + delivery_not_sent`，需另行显式排期。其他项的历史尝试计数保留，未知、发送中、已送达记录及其他内容或目标不受该更新影响。核对接口本身不调用平台。已知发送结果不因迟到 worker 的成功、失败或取消被覆盖。

普通重试、取消、重新排期、force enqueue、Agent 批量推送均不能清除 `delivery_unknown`。内容详情后处理面板将它显示为需要核对的 blocked，而非批量重试项。Telegram 媒体发送遇到网络异常不再退化成另一条媒体/文本发送；保守转入核对，不能把丢失回执解释为没有送达。

这里不承诺平台 exactly-once：核对依赖用户在目标会话中的实际观察，停止已发起的网络请求也不等于撤回远端消息。

### 媒体推送（2026-09-26）

发现同步在入库及归档后同步维护媒体资产。推送正文先解析 Markdown、移除图片节点和内部存储引用，再生成平台文本；图片通过资产上传，不把路径作为正文发送。Telegram 超过 10 项按顺序分批，长正文分为完整文本消息；本地文件缺失不会静默改发文字。静态图片仅在上传时临时编码 JPEG，归档 WebP 不增加永久副本；动画图片及非播放器支持格式使用文件发送。QQ 使用同一正文清理和资产契约，上传前确认本地文件存在。
