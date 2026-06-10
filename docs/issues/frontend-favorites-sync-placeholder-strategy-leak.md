# 收藏同步 placeholder 策略暴露给用户

## 状态

active

## 现象

- 收藏同步面板向用户展示并允许选择“收藏夹/分组接口预留”“全量回填接口预留”“标记归档接口预留”等策略。
- `favorites_sync_provider.dart` 明确将 `collections_api_placeholder`、`full_backfill_placeholder`、`mark_archived_placeholder` 作为可识别状态。
- 这些策略名称说明它们只是平台能力或后端流程的预留位，但前端把它们做成了可配置项。

## 影响范围

- 页面：自动化页收藏同步 tab、设置页 AI/自动化 tab。
- 后端模块：favorites-sync、config-system。
- 数据：favorites sync settings、同步策略字段。
- 用户影响：用户会误以为选择这些策略会改变同步行为，实际只是保留抽象或未实现能力，造成配置欺骗和验收困难。

## 复现方式

1. 打开 `/automation?tab=favorites`。
2. 在“同步策略”卡片中查看同步范围、首次同步、取消收藏等配置。
3. 选择带“接口预留”的选项。
4. 检查说明文案，确认这些选项不会真正启用对应平台能力。

## 根因分析

- AI 生成代码把未来平台能力和内部策略占位直接暴露为用户可选项。
- 设置字段缺少“已实现能力”和“预留字段”的边界，前端为了展示完整策略而泄漏未实现 contract。
- 自动化页承担过多配置职责，导致占位策略被包装成产品功能。

## 关联代码

- `frontend/lib/features/review/widgets/favorites_sync_automation_panel.dart`
- `frontend/lib/features/settings/presentation/tabs/automation_tab.dart`
- `frontend/lib/features/settings/providers/favorites_sync_provider.dart`
- `backend/app/tasks/favorites_sync.py`
- `backend/app/routers/system.py`

## 关联文档

- `../frontend/pages/automation.md`
- `../frontend/pages/settings.md`
- `../backend/modules/favorites-sync.md`
- `frontend-automation-page-responsibility-overload.md`
- `frontend-control-policy-gaps.md`

## 修复建议

- 最小修复：从用户可见下拉/选择器中移除所有 `*_placeholder` 选项，只保留已实现且可验证的策略。
- 后端若仍需保留字段，应作为内部兼容值处理，不在前端暴露，也不写成当前能力。
- 如未来实现收藏夹/全量回填/远端取消收藏差异检测，应先建 plan 和 API contract，再恢复对应 UI。

## 验证方式

- 自动测试：收藏同步面板和设置页 widget 测试确认不出现“接口预留”“placeholder”等文案。
- 手动验收：用户只能选择当前真实生效的同步策略。
- 回归检查：`rg -n "placeholder|接口预留" frontend/lib/features/review frontend/lib/features/settings` 不应命中用户可见文案。
