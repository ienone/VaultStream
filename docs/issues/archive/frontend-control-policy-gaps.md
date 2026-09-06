# 前端控制面与后端自动化策略缺口

## 状态

archived

## 关闭结论

原问题把多个尚未核对的入口概括成“前端开关不能约束后端”，范围过宽。逐条沿真实 producer 核对后，已有策略和本轮修复已覆盖当前设置页公开的自动化控制：

- 收藏同步的定时、手动、失败重试和 Agent 入口复用平台策略。
- 禁用发现源会阻止定时和手动同步；发现巡逻与 AI 评分在自动 post-ingest 入口读取对应策略。
- 自动摘要、自动语义索引和解析 worker 在调用 provider 或领取任务前读取持久设置；用户显式摘要/索引动作保持独立。
- 媒体归档总开关、图片/视频子开关和限制参数覆盖新解析、已解析内容补处理与发现入库；视频补处理遗漏和 JSON 落库问题已修复。
- Cookie 保活在每次平台访问前动态读取设置，重新开启不需要重启。
- `distribution_mode=paused` 会阻止自动审批、规则刷新产生的新自动审批、enqueue、worker 和 Agent 批量推送；规则刷新仍可撤销已失效的旧自动审批，人工审核保持可用。
- 通用 Agent API bridge 不允许借通用 mutation 绕过外部同步、发送、设置和队列策略。

本 issue 不继续承载“未来可能新增入口”的泛化风险。新增 producer 应在其功能切片中按实际 contract 补策略与测试；出现具体绕过时再建立聚焦 issue。

## 已修复根因

缺口不是缺少统一策略类，而是少数 producer 没有在副作用发生前动态读取既有持久策略：解析 worker、Cookie 保活循环和分发自动审批/规则刷新属于此类。另有媒体视频补处理遗漏、摘要开关重复入口等领域问题。修复均复用已有设置和 `AutomationPolicyService`，没有增加平行开关或兼容路径。

## 分发专项证据

`DistributionService.auto_approve_if_eligible()` 现在先检查 `distribution_enqueue` 策略；暂停时不会把 `PENDING` 提升为 `AUTO_APPROVED`。`refresh_queue_by_rules()` 每轮读取同一策略，暂停时只执行撤销旧自动审批这一安全收敛动作，不产生新的审批或 enqueue。

单元测试覆盖暂停时的 post-ingest 自动审批和规则刷新，并验证旧自动审批仍能撤销。仓库实验数据库探针临时写入一条匹配规则和一条解析成功内容，确认 `auto_approved=false`、状态仍为 `pending`、enqueue 调用 0、队列项 0，随后精确清理探针记录并恢复原设置；没有使用独立 `/tmp` 数据库或真实推送平台。

## 验证结果

- 分发服务专项测试：11 passed。
- 后端非 integration 主套件：942 passed、4 skipped、9 deselected。
- 需要绑定本机端口的开发控制器测试在沙盒外单独运行：10 passed。
- 当前后端合计：952 passed。
- Flutter analyze 无问题，完整 widget/unit 套件 175 passed（本次分发修复未改前端）。
- 仓库数据库探针均恢复临时设置并清理精确创建的记录；未执行外部平台、真实模型或部署验收。

## 关联文档

- `../../backend/modules/distribution.md`
- `../../backend/modules/events-tasks.md`
- `../../backend/modules/favorites-sync.md`
- `../../backend/modules/accounts-auth.md`
- `../../backend/modules/media.md`
- `../../frontend/pages/settings.md`
- `favorites-sync-retry-policy-gap.md`
- `backend-agent-api-bridge-policy-bypass.md`
