# 自动化页职责拆分修复记录

## 状态

archived

## 现象

- 旧 `/automation` 曾在同一页面聚合分发、收藏同步、平台健康、解析诊断和推送历史，并通过多个复杂弹窗承载对象编辑与任务结果。
- 修复后首屏只保留自动化总览及收藏同步、分发、解析 / 后处理三域；分区和复杂规则均有稳定 URL。

## 影响范围

- 页面：`/automation`。
- 前端模块：`frontend/lib/features/automation/*`。
- 后端模块：distribution、favorites-sync、events-tasks。
- 原用户影响：自动化页曾变成多业务“控制台”，用户难以区分分发、同步、诊断和历史。

## 复现方式

1. 打开 `/automation`。
2. 从自动化总览进入收藏同步、分发、解析 / 后处理三个域。
3. 在分发域新建规则，或从规则卡进入编辑。
4. 当前会分别进入 `/automation/distribution/rules/new` 或 `/automation/distribution/rules/:ruleId`，返回后回到分发域；不再打开规则 dialog。

## 根因分析

- 旧分发审核页面在没有重新划分信息架构的情况下持续吸纳收藏同步、平台健康和任务结果能力。
- “自动化”被当成所有后台副作用的容器，而不是按用户任务拆分为分发、同步、诊断、历史和任务结果。
- 子组件直接承担 API 写操作和业务 run 详情，缺少独立页面或统一 task renderer。

## 已完成

- 将 `/automation` 首屏从 4 个顶层 tab 重组为自动化总览。
- 总览直接展示收藏同步、分发、解析 / 后处理三张域入口卡；待分发、已推送和启用范围进入各自卡片，删除重复的欢迎块和四张独立指标卡。
- 将分发队列和推送历史收敛为分发域内的局部 `SegmentedButton` 切换。
- 总览、收藏同步、分发队列、推送历史和解析 / 后处理已分别拥有稳定 URL；总览卡、分发局部切换和任务结果链接统一更新地址栏，刷新可还原当前分区。
- 保留旧 `/review` 删除状态，未新增 redirect 或 fallback。
- 总览删除独立“需要处理”面板，只保留三个领域入口和最小运行概况；异常回到所属阶段或运行详情。
- `/automation/processing` 不再复用账号、发现源和推送目标健康矩阵，现按解析、媒体归档、摘要/OCR/转写和全文/语义索引展示真实策略、数量、失败内容和最近 run。
- 旧 health/matrix/diagnostics 等内部 tab 别名与被替代的健康矩阵组件已删除；账号问题只进入独立账号中心，任务结果只进入 `/tasks/:runId`。
- 复杂规则新建和编辑迁到独立全屏 surface，复用原有 typed provider、目标差异更新和回填预览/确认 contract；旧规则 dialog 路径已删除。

## 关联代码

- `frontend/lib/features/automation/automation_page.dart`
- `frontend/lib/features/automation/distribution_rule_page.dart`
- `frontend/lib/features/automation/widgets/favorites_sync_automation_panel.dart`
- `frontend/lib/features/automation/widgets/processing_automation_panel.dart`
- `frontend/lib/features/automation/widgets/rule_config_panel.dart`
- `frontend/lib/features/automation/widgets/queue_content_list.dart`

## 关联文档

- `../frontend/pages/automation.md`
- `archive/automation-review-doc-source-split.md`
- `archive/frontend-account-entry-responsibility-duplication.md`
- `archive/task-run-result-contract-missing.md`
- `archive/frontend-control-policy-gaps.md`

## 关闭结论

- 已满足原问题的 Section Shell 与复杂规则 Detail Shell 关闭条件。
- 后续只有在处理阶段出现新的独立用户任务时再增加下钻，不把配置表单或完整 run 结果复制回自动化页。

## 验证方式

- 自动测试：自动化页 widget 测试确认首屏展示三个领域入口、不存在顶层 `TabBar`，验证分区、规则新建和规则编辑 URL 可恢复；规则编辑器测试覆盖创建、编辑和窄屏布局。
- 手动验收：用户能从总览进入三个领域，通过返回按钮回到总览，并从规则列表进入独立规则页面。
- 结构检查：`AutomationPage` 不使用顶层 `TabController` / `TabBarView`，也不构造 `DistributionRuleEditor` 或规则写请求。
