# 持续处理：中断接续与事件证据保留缺口

## 状态与范围

active · 2026-09-14 隔离复现，未修复业务实现。对应[整体方案第 0 阶段](../plans/2026-09-14-product-architecture-review.plan.md#sequence)。

本轮验证的是三个独立、可构造的失效状态，不是用户生产库已发生数据丢失的报告。测试使用仓库根虚拟环境、正式 ORM 与真实 SQLite；无真实平台、模型或发送调用。临时验收结束后移除脚本，保留下面的复现条件与实际结果，修复时再加入必要的长期完整性回归。

## CP-01：解析队列遗留 RUNNING 不会接续

**复现：** 向隔离库提交一个 `task_type=parse_content` 的 Task，状态 RUNNING，`started_at` 为一天前；重新创建并连接 TaskQueue，调用 `dequeue(timeout=1)`。实际返回 None，遗留任务未被领取。

[领取逻辑](../../backend/app/core/queue_adapter.py#L81-L127)只选择 PENDING，再 CAS 改成 RUNNING，没有执行租约/到期回收。[解析取消处理](../../backend/app/tasks/parsing.py#L112-L131)确实会结算可捕获的 CancelledError；因此不能泛化为“任何正常停机必卡住”。本问题针对进程硬中断、未执行 finally 或同等遗留状态。

**影响：** 已入库材料可能长期显示处理中；再次创建服务和运行轮询不等于恢复。人工重解析可能绕开故障，但不是自动化接续。

**关闭条件：** 为执行建立明确租约/所有者与到期处理；在安全、幂等的解析阶段有界恢复，已删除内容跳过，人工字段保护不回退。验证新 worker 能接续过期任务、不能抢活跃任务，迟到旧 worker 不能覆盖新结果或结算别人的租约。

## CP-02：分发锁有过期条件，但 PROCESSING 不进入候选

**复现：** 创建可用 BotConfig、启用且可访问的 BotChat、规则、目标与可读 Content；提交一个 PROCESSING 队列项，`locked_at` 为一天前、`locked_by=dead-worker`。新 worker 调用 `_claim_items`，实际领取集合为空，行仍是 PROCESSING。

[领取查询](../../backend/app/tasks/distribution_worker.py#L307-L474)在共同条件中检查锁到期，但状态只接受 SCHEDULED 或到重试时间的 FAILED；不能从“存在 LOCK_TIMEOUT”推断发送中断会恢复。

**不能直接改为自动重发：** [实际发送顺序](../../backend/app/tasks/distribution_worker.py#L638-L679)先调用平台 push，再提交 message_id、SUCCESS 与 PushedRecord。远端已接受而本地未提交时结果未知；本轮没有模拟真实平台接受后崩溃，风险来自这条明确的非原子调用链。平台未提供真实可用的幂等键/查询 contract 时，不能承诺 exactly-once。

**关闭条件：** 超时运行态必须被归类，不再永久卡住。区分未发送、明确失败、结果未知；前两类按资格恢复，未知进入核对流程。发送前复查目标/策略/授权，恢复不能绕开当前暂停或造成重复外发；页面和消息提供对应核对动作，不只“重试全部”。

## CP-03：候选 TTL 会留下失去来源成员的综合事件

**复现：** 创建两条 VISIBLE、一天前到期的 Content，作为同一事件的 SOURCE；另一条无候选 TTL 的生成 Content 作为 REPORT。隔离配置设为 `discovery_cleanup_mode=hard_delete`，执行真实 `_cleanup_expired()`。实际两条来源内容被删除，事件成员仅剩 REPORT。

[清理任务](../../backend/app/tasks/discovery_cleanup.py#L64-L154)先把过期 VISIBLE 改为 EXPIRED，然后按候选状态和到期时间删除内容及来源、索引、队列、推送记录；没有事件引用保留条件。[成员外键](../../backend/app/models/knowledge_event.py#L94-L108)随 Content 删除级联移除。生成稿仍可能留有复制引句和外部 URL，但原文对象、来源历史、完整上下文与内部证据关系已经消失，不能称为证据完整。

**影响：** 自动聚合越多，用户越可能得到“结论还在，证据已丢”的系统；不同于已收录 PROMOTED 内容受现有候选条件保护。本轮只对 hard_delete 做删除复现，archive/expire_only 的阅读与索引影响需在修复时单独检查。

**关闭条件：** 到期策略只影响未采纳且无依赖的候选。先保证事件成员原文与关联不被独立 TTL 清理；随后明确已发送产物、引用版本和用户保存的保留规则。证明未引用过期候选仍可清理、被引用候选仍能阅读和检索；用户主动不可逆擦除走单独影响确认，不偷偷保留要求擦除的材料。

## 同批处理与验证记录

CP-01/02 共享“领取、租约、恢复、迟到结果”的设计原则，但解析与外部发送不能合成同一个重试规则。CP-03 与自动聚合的来源选择、事件引用和保留策略一起修；不要在清理任务中临时硬编码生成稿 ID 或把所有候选永久保留。

本轮临时验收最终 **3 failed in 1.26s**，三个断言分别针对上述行为；没有改断言把错误变绿。移除临时脚本后，现有长期后端回归 **160 passed in 5.64s**，不覆盖或否定这三个缺口。环境及调用证据见[重审取证 E7](../knowledges/product-review-2026-09-14/README.md#e7)。
