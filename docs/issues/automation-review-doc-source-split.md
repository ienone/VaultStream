# 自动化页与旧 Review 模块文档并存导致职责来源分裂

## 状态

active

## 现象

- 权威文档 `docs/frontend/pages/automation.md` 将 `/automation` 描述为自动化聚合页，当前包含分发队列、收藏同步、健康矩阵和推送历史。
- 代码目录内仍存在 `frontend/lib/features/review/README.md`，标题为 “Review & Distribution 模块”，只描述审核、分发规则、Bot 和推送历史，未覆盖收藏同步和健康矩阵。
- 路由仍保留 `/review` 到 `/automation` 的别名，页面实现类仍叫 `ReviewPage`。

## 影响范围

- 页面：`/automation`、`/review`。
- 前端模块：`frontend/lib/features/review/*`。
- 文档：`docs/frontend/pages/automation.md`、`docs/frontend/navigation.md`、代码目录 README。
- 用户影响：新贡献者或 agent 可能按旧 review/distribution 口径继续扩展，而不是按照当前文档约束拆分自动化、分发、同步和诊断边界。

## 复现方式

1. 打开 `docs/frontend/pages/automation.md`。
2. 打开 `frontend/lib/features/review/README.md`。
3. 对比两者对页面职责的描述。
4. 打开 `frontend/lib/routing/app_router.dart`，确认 `/automation` 使用 `ReviewPage`，`/review` redirect 到 `/automation`。

## 根因分析

- 页面从 Review/Distribution 演化为 Automation 聚合页后，代码目录命名和 README 没有同步收敛。
- `/review` 兼容别名、`ReviewPage` 类名和 `features/review` 目录继续暗示旧职责。
- 现有污染总表提到了命名不一致，但没有把“代码目录 README 与权威文档口径冲突”单独列为治理问题。

## 关联代码

- `frontend/lib/routing/app_router.dart`
- `frontend/lib/features/review/review_page.dart`
- `frontend/lib/features/review/README.md`
- `frontend/lib/features/review/widgets/favorites_sync_automation_panel.dart`
- `frontend/lib/features/review/widgets/automation_health_matrix_panel.dart`

## 关联文档

- `../frontend/pages/automation.md`
- `../frontend/navigation.md`
- `frontend-automation-page-responsibility-overload.md`

## 修复建议

- 最小修复：将 `frontend/lib/features/review/README.md` 改为历史说明，只指向 `docs/frontend/pages/automation.md`，不再维护竞争性职责定义。
- 中期修复：明确 `/review` 是否只是临时兼容别名；如无外部兼容需求，按重构规则删除旧路径。
- 长期修复：为自动化页拆分建立 plan，决定是否重命名 `ReviewPage` 和 `features/review`，避免三套命名长期并存。

## 验证方式

- 文档检查：`rg -n "Review & Distribution|ReviewPage|/review|/automation" docs frontend/lib/features/review/README.md`。
- 手动验收：导航、深链接和页面标题仍正常；代码目录 README 不再与权威文档冲突。
- Review：确认旧 `/review` 的保留或删除有明确 owner 和验收标准。
