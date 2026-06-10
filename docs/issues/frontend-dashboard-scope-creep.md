# 动态页继续承载收藏统计、跨页面筛选和 run 详情

## 状态

active

## 现象

- 动态页顶部统计仍包含总内容、存储占用、平台分布、增长趋势等收藏库专属统计。
- 点击统计卡会直接写入 `collectionFilterProvider`，再跳转收藏库，形成跨页面状态迁移。
- 活动时间线仍通过底部抽屉展示 run metadata/result JSON，并根据任务类型跳转“相关工作区”，而不是统一进入 `/tasks/:runId`。

## 影响范围

- 页面：动态页、收藏库、任务结果页。
- 前端状态：dashboard stats、collection filter、background task run。
- 后端模块：contents、events-tasks、favorites-sync、distribution、discovery。
- 用户影响：动态页从全局近期状态膨胀为收藏统计页和任务详情入口；收藏库和任务页的职责被稀释。

## 复现方式

1. 打开 `/home`。
2. 查看顶部统计、平台分布和增长趋势。
3. 点击统计卡跳转收藏库，观察动态页直接修改收藏筛选 provider。
4. 打开活动时间线 run 详情，观察底部抽屉展示 metadata/result JSON 并提供“打开相关工作区”。

## 根因分析

- 动态页早期作为总览页承载了过多统计，后续没有把收藏域统计迁回收藏库。
- 跨页面筛选通过共享 provider 直接写入，而不是通过明确路由参数或收藏页自身入口管理。
- 任务结果页已经存在，但动态页仍保留 run detail 弹层，导致任务结果展示分裂。

## 关联代码

- `frontend/lib/features/dashboard/dashboard_page.dart`
- `frontend/lib/features/dashboard/widgets/activity_timeline_card.dart`
- `frontend/lib/features/dashboard/widgets/platform_distribution_card.dart`
- `frontend/lib/features/dashboard/widgets/growth_chart_card.dart`
- `frontend/lib/features/collection/providers/collection_filter_provider.dart`
- `frontend/lib/features/dashboard/task_result_page.dart`

## 关联文档

- `../frontend/pages/dashboard.md`
- `../frontend/pages/collection.md`
- `../frontend/pages/tasks.md`
- `../frontend/components/task-result.md`
- `task-run-result-contract-missing.md`

## 修复建议

- 最小修复：动态页的 run 查看入口统一跳转 `/tasks/:runId`，停止展示 raw JSON 底部抽屉。
- 中期修复：收藏库专属统计迁移到收藏页；动态页只保留全局近期状态、异常摘要和跳转。
- 长期修复：跨页面筛选改为明确 route query/deep link contract，避免动态页直接写收藏页 provider。

## 验证方式

- 自动测试：动态页点击 run 时路由到 `/tasks/:runId`；收藏过滤通过路由参数或收藏页入口恢复。
- 手动验收：动态页不再展示完整收藏统计和 run raw JSON；收藏库承担收藏统计和筛选。
- 回归检查：`rg -n "collectionFilterProvider|showModalBottomSheet" frontend/lib/features/dashboard` 不应命中跨页面筛选写入和 run detail 弹层。
