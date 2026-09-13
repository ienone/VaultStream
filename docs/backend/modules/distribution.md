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
