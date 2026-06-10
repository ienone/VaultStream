# 账号中心、设置页和健康矩阵重复承担账号职责

## 状态

archived

## IA 处置结论

- 处置类型：`resolved_by_removal`。
- 处置说明：旧 `/accounts` 兼容路由和 `frontend/lib/features/accounts/account_center_page.dart` 已删除；设置页改为 Section Shell 的“账号与平台”分区，当前只保留平台健康只读摘要；自动化健康矩阵只跳转设置账号分区，不再提供账号连接/解绑主流程。因此“三处同时承担账号主流程”的重复职责问题已通过删除旧独立账号中心和旧兼容入口关闭。后续账号连接、检测、解绑能力需要按新设置分区重新实现，而不是恢复旧页面。
- 最近更新：2026-06-11。

## 现象

- `/accounts` 被文档定义为平台账号状态和连接动作的唯一主入口，但设置页连接 tab 仍展示平台健康列表，并提供扫码/浏览器连接、检测、解绑等账号动作。
- 自动化页健康矩阵的“平台账号”section 也读取平台健康状态，并提供检测登录、查看最近同步、解析测试等操作。
- 三处页面都展示平台账号、Cookie、收藏同步认证和修复入口，用户无法判断账号问题应在哪个页面处理。

## 影响范围

- 页面：账号中心、设置页连接 tab、自动化页健康矩阵。
- 后端模块：accounts-auth、favorites-sync、config-system。
- 数据：平台 Cookie、browser auth 状态、收藏同步认证状态、平台健康摘要。
- 用户影响：账号修复路径重复且不一致；后续改动容易在其中一处遗漏状态、文案或策略检查。

## 复现方式

1. 打开 `/accounts`，查看平台健康卡片和连接/检测操作。
2. 打开 `/settings?tab=connection`，查看平台健康摘要和平台设置区的连接、检测、解绑操作。
3. 打开 `/automation?tab=health`，查看平台账号 health row 的检测登录和最近同步入口。
4. 对比三处页面，确认它们都在承担账号状态判断或修复入口。

## 根因分析

- 账号状态最初作为设置项和自动化诊断的一部分被逐步塞入多个页面，后来新增账号中心后没有删除旧入口。
- 前端缺少“账号主流程唯一入口”的硬边界，设置页和健康矩阵没有降级为只读摘要或跳转入口。
- 平台健康 API 同时包含登录、Cookie、收藏同步和最近 run 信息，前端页面容易把完整数据都展示为可操作工作流。

## 关联代码

- `frontend/lib/features/accounts/account_center_page.dart`
- `frontend/lib/features/settings/presentation/tabs/connection_tab.dart`
- `frontend/lib/features/automation/widgets/automation_health_matrix_panel.dart`
- `frontend/lib/features/settings/providers/platform_health_provider.dart`
- `backend/app/routers/system.py`

## 关联文档

- `../frontend/pages/accounts.md`
- `../frontend/pages/settings.md`
- `../frontend/pages/automation.md`
- `../backend/modules/accounts-auth.md`
- `../backend/modules/config-system.md`

## 修复建议

- 最小修复：按当前 IA 目标，账号连接、检测、解绑和修复主流程应进入设置 Section Shell 的“账号与平台”强子页；设置页其他分区和自动化健康矩阵只保留摘要或跳转，不重复执行账号主流程。
- 健康矩阵只展示平台账号状态摘要和“前往账号与平台”跳转，不再提供检测登录、连接或解绑主流程。
- 账号健康 API 可继续作为共享读取来源，但可执行账号动作必须由账号中心 controller/provider 统一封装。

## 验证方式

- 自动测试：设置页和健康矩阵 widget 测试确认不再出现账号连接/解绑主按钮。
- 手动验收：从设置页其他分区和自动化页遇到账号问题时，只能跳转“账号与平台”处理。
- 回归检查：`rg -n "InteractiveLoginDialog|browser-auth/.*/check|browser-auth/.*/logout|DELETE.*/browser-auth" frontend/lib/features/settings frontend/lib/features/automation` 不应命中可执行账号主流程。

本次关闭验证：`frontend/lib/routing/app_router.dart` 已无 `/accounts` 路由，`frontend/lib/features/accounts/account_center_page.dart` 已删除；设置和自动化侧只保留“账号与平台”分区入口。
