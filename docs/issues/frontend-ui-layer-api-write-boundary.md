# 前端 UI 层直接执行大量 API 写操作

## 状态

active

## 现象

- 多个页面 widget 或展示组件直接读取 `apiClientProvider` 并执行 POST/PATCH/DELETE 写操作。
- 已确认例子包括 Agent 页面直接管理 SSE 和会话 API、内容详情后处理面板直接执行摘要/语义/分发/巡逻写操作、自动化健康矩阵直接调用解析测试等。旧账号中心和旧 Discovery action provider 已删除，不再作为当前问题例子。
- 这些写操作通常同时承担 toast、provider invalidate、弹窗关闭、路由跳转和错误格式化，导致 UI 组件变成业务 controller。

## 影响范围

- 页面：Agent、内容详情、设置页、自动化页。
- 后端模块：agent、contents、search-rag、distribution、accounts-auth、discovery、favorites-sync。
- 数据：会话、内容后处理状态、平台认证状态、发现候选状态、任务 run。
- 用户影响：同类动作在不同页面错误处理和刷新行为不一致；API contract 漂移时难以集中修复。

## 复现方式

1. 搜索前端代码中的 `ref.read(apiClientProvider)`、`.post(`、`.patch(`、`.delete(`。
2. 检查命中位置是否位于 page/widget 文件，而不是 provider/controller/action service。
3. 观察这些 widget 是否同时处理业务状态、toast、刷新和导航。

## 根因分析

- AI 生成代码倾向于在当前可见 widget 内就地补按钮和 API 调用，缺少 provider/controller 层约束。
- 前端没有明确 action service 或 controller 命名规则，导致展示组件直接拥有副作用。
- 后端动作型 API 也存在 inline contract 问题，进一步鼓励前端用动态 map 猜字段。

## 关联代码

- `frontend/lib/features/agent/agent_page.dart`
- `frontend/lib/features/collection/widgets/detail/components/post_processing_status_panel.dart`
- `frontend/lib/features/settings/presentation/tabs/connection_tab.dart`
- `frontend/lib/features/automation/widgets/automation_health_matrix_panel.dart`

## 关联文档

- `../frontend/README.md`
- `frontend-agent-page-controller-and-sse-boundary.md`
- `frontend-post-processing-panel-side-effects.md`
- `archive/frontend-account-entry-responsibility-duplication.md`
- `archive/frontend-discovery-placeholder-actions-leak.md`
- `backend-diagnostic-api-contract-is-inline.md`

## 修复建议

- 最小修复：禁止新增 page/widget 内直接写 API；新增写操作必须进入 provider/controller/action service。
- 中期修复：为后处理、Agent、收藏同步和独立账号中心分别建立 typed action provider，统一 loading、错误、toast、刷新和路由结果。
- 长期修复：前端 API client 返回 typed model；动作型 API 的 `run_id`、policy error 和 validation error 通过统一 contract 处理。

## 验证方式

- 静态检查：`rg -n "ref\.(read|watch)\(apiClientProvider\).*|\.post\(|\.patch\(|\.delete\(" frontend/lib/features` 后人工确认写操作不在纯 UI widget 中。
- 自动测试：action provider 单元测试覆盖成功、失败、policy denied、run_id 返回。
- 手动验收：同类动作在不同页面显示一致 loading、错误和成功反馈。
