# 动态页仍是迁移说明与发现概览，尚未形成内容流

## 状态

archived

## 原问题

旧 `/home` 以迁移说明、发现统计和整页入场动画占据首屏，没有真实候选条目，用户无法直接浏览或处理近期内容。

## 关闭证据

- `frontend/lib/features/dashboard/dashboard_page.dart` 已使用 discovery 候选作为连续信息流，展示来源、时间、正文预览和统一媒体资产。
- 页面已删除迁移说明、统计概览、后台 diagnostics 和整页重复入场动画。
- 收录、忽略、撤销和稍后处理均写入后端持久状态；“新动态 / 稍后处理”读取不同 API 状态，稍后条目可移回新动态。
- 操作区使用可换行布局，widget 测试覆盖常规宽度和 360×800 Compact 视口。
- 仓库实验数据库的真实 API 探针验证 `visible → snoozed → visible`，默认流和稍后列表随持久状态切换；探针记录已按 ID 清理。

## 保留边界

事件变化、批次摘要、来源偏好和更完整的主动探索仍是独立功能目标，不属于本 issue 原“页面没有内容流”的关闭条件。

## 验证

- `backend/tests/test_api/test_discovery_api.py`
- `frontend/test/unit/discovery_feed_provider_test.dart`
- `frontend/test/widget/dashboard_page_test.dart`
