# 自动化页与旧 Review 命名分裂

## 状态

archived

## 处置结论

resolved_by_removal

## 原现象

- `/automation` 页面已经承担自动化聚合页职责，但代码仍位于 `frontend/lib/features/review/`。
- 路由 `/automation` 使用 `ReviewPage`，页面文件名仍为 `review_page.dart`。
- `frontend/lib/features/review/README.md` 作为历史说明存在，容易让后续贡献者继续按旧 Review / Distribution 语义扩展。

## 本轮修复

- 将 `frontend/lib/features/review/` 迁移为 `frontend/lib/features/automation/`。
- 将 `review_page.dart` / `ReviewPage` 收敛为 `automation_page.dart` / `AutomationPage`。
- 更新 `frontend/lib/routing/app_router.dart`，`/automation` 直接使用 `AutomationPage`，未恢复 `/review` 路由或 redirect。
- 更新跨模块 import、自动化相关测试命名和自动化模块 README。
- 同步更新 `docs/frontend/pages/automation.md`、`docs/frontend/navigation.md`、`docs/issues/README.md` 和 IA process。

## 保留问题

- 本 issue 只处理命名与结构来源分裂。
- 自动化页仍是一级 4 tab 聚合 UI，自动化三域化继续由 `../frontend-automation-page-responsibility-overload.md` 跟踪。

## 验证方式

- 结构检查：`rg -n "features/review|features\\review|ReviewPage|review_page|frontend/lib/features/review|lib/features/review|package:frontend/features/review|\.\./\.\./review|\.\./\.\./\.\./review" frontend` 应无命中。
- 文档检查：`rg -n "frontend/lib/features/review|ReviewPage|review_page|features/review" docs/frontend docs/issues --glob "!archive/**"` 不应在当前文档或 active issue 中命中；归档原现象和 process 历史记录可保留旧名称。
- 路由检查：`rg -n "/review|AutomationPage|features/automation/automation_page" frontend/lib/routing docs/frontend/navigation.md` 应只保留 `/review` 已删除说明和 `/automation` 使用 `AutomationPage` 的当前事实。
