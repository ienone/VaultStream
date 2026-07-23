# 动态页仍是迁移说明与发现概览，尚未形成内容流

## 状态

active

## 处置说明

旧问题所述收藏统计、跨页面筛选写入和活动时间线 run 弹层已经从当前 `DashboardPage` 删除。2026-07-24 复核后，本 issue 改为只追踪仍然存在的动态页职责与可用性问题。

## 现象

- `/home` 当前由一张“正在过渡为个人信息流”的迁移说明卡和一张 `DiscoveryOverviewCard` 组成。
- 页面仍以发现统计概览代替真实内容条目，没有形成可滚动的订阅、发现和事件更新流。
- 页面根部对整个 `SingleChildScrollView` 使用 600ms `fadeIn`；迁移说明本身占据首屏视觉重点，却不提供可完成的用户任务。
- “推荐候选”仍是统计/入口式概览，不是具备来源、时间、内容预览和轻量主动作的候选条目。

## 影响范围

- 页面：动态页。
- 前端状态：discovery stats 与未来的动态候选流。
- 后端模块：discovery、contents、events-tasks。
- 用户影响：用户进入动态页后仍看不到“现在有什么值得看”，首屏被未来说明和概览卡占据。

## 复现方式

1. 打开 `/home`。
2. 查看首屏“动态正在从系统仪表盘过渡为个人信息流”说明卡。
3. 查看“推荐候选”区域，确认当前只展示发现概览而非内容条目。
4. 刷新或重建页面，观察整个页面重复执行入场 fade。

## 根因分析

- 旧 Dashboard 的统计和任务职责已被删除，但真实动态候选 contract 与内容流尚未接上。
- 过渡阶段用说明卡和概览卡填补空白，导致实现状态被直接暴露给用户。
- 页面级动效没有区分首次进入、刷新和 provider rebuild。

## 关联代码

- `frontend/lib/features/dashboard/dashboard_page.dart`
- `frontend/lib/features/dashboard/widgets/discovery_overview_card.dart`
- `frontend/lib/features/discovery/providers/discovery_stats_provider.dart`

## 关联文档

- `../frontend/pages/dashboard.md`
- `../plans/2026-06-10-frontend-information-architecture-redesign.plan.md`

## 修复建议

- 删除迁移说明卡，不在产品 UI 中解释内部迁移过程。
- 用真实候选条目替换发现统计概览；每项只显示标题、必要预览、来源/时间和一个轻量主动作。
- 不展示内部评分、“为什么推荐”或模型式可信说明。
- 移除整页重复入场动画，只为明确的局部状态变化提供语义动效。

## 验证方式

- Widget 测试：动态页渲染真实候选条目，不出现迁移说明文案。
- 手动验收：首屏能直接回答“现在有什么值得看”，刷新时不重复整页入场。
- 回归检查：`rg -n "正在从系统仪表盘过渡|\.animate\(\)\.fadeIn" frontend/lib/features/dashboard` 不应命中当前动态页。
