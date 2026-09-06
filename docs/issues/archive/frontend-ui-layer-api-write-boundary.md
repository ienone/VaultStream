# 前端 UI 层直接执行大量 API 写操作

## 状态

archived

## 关闭结论

前端 `page`、`widgets` 和设置 tab 中已不再直接调用 `apiClientProvider` 的 POST/PATCH/DELETE。页面负责表单、用户确认、导航和结果提示；endpoint、payload、动态响应解析、pending 防重和相关 provider 刷新由领域 provider/controller 承担。

这不表示所有前端返回值已经由代码生成模型覆盖。后端动作型 API 的 inline dict 已由 `backend-diagnostic-api-contract-is-inline.md` 独立收敛；本 issue 只关闭 UI 展示层直接拥有写请求的问题。

## 已完成

- 内容捕获、编辑、删除、重解析和解析候选处理统一经过 `ContentActions`。
- 内容详情旧后处理面板已删除，详情不再直接触发跨领域处理写操作。
- Agent、平台认证、发现源和自动化健康动作使用各自 controller/provider。
- 设置页失败语义索引重试由 `SemanticIndexActions` 返回 typed `runId`。
- `PushTab` 的 Bot 配置保存、Telegram 服务控制、Bot 配置解析和群组同步迁入 `BotConfigActions`；页面不再解析 Bot API map。
- 引导页复用 `SystemSettings`、`AiModelDiscoveryActions` 和 `BotConfigActions`，不再直接写设置、模型发现或 Bot 配置 API。
- 自动化页的立即重推进入 `PushedRecords` notifier，并在同一动作边界刷新队列、统计和筛选状态。
- 未被路由或调用方引用的旧 `BotManagementPage` 及其私有 `BotConfig` 模型已删除，没有保留第二套 Bot 管理写路径。

## 验证

- 静态扫描 `frontend/lib/features` 下 page/widget/settings tab 的 `apiClientProvider` 与 POST/PATCH/DELETE：无命中。
- provider 单测覆盖语义失败重试、模型发现、Bot 配置更新与立即重推的真实 path、payload 和 typed 结果/状态迁移。
- 引导页、自动化页和推送设置聚焦回归：19 passed。
- `flutter analyze --no-pub`：No issues found。
- `flutter test --no-pub`：179 passed。
- 未调用真实模型、Bot、推送目标或外部平台；本地测试不等于部署验收。

## 关联文档

- `../../frontend/README.md`
- `../../frontend/pages/settings.md`
- `../../frontend/pages/automation.md`
- `frontend-post-processing-panel-side-effects.md`
- `frontend-agent-page-controller-and-sse-boundary.md`
- `backend-diagnostic-api-contract-is-inline.md`
- `backend-bot-config-router-side-effects.md`
