# Agent 页面构建阻断与 UI 层职责污染

## 状态

仅完成最小修复，确保页面可构建；中期和长期修复涉及较大重构，待其余部分完成后再回过头来细化和修复这个问题。

## 现象

- `frontend/lib/features/agent/agent_page.dart` 当前包含 `queryParameters: {'message': text, 'session_id': ?_sessionId}`，`?_sessionId` 不是合法 Dart 表达式，会直接阻断前端构建或分析。
- 同一页面文件约 900 行，直接负责会话列表加载、新建/选择会话、SSE HTTP 连接、事件解析、确认决策、redo、stop、clear、timeline 本地状态和错误展示。
- 页面通过 `apiClientProvider` 和 `http.Client` 直接拼接 `/agent/sse` 请求，并用动态 `Map<String, dynamic>` 和字符串分支解释后端事件。

## 影响范围

- 页面：`/agent` Agent 工作台。
- 后端模块：Agent SSE、Agent session、Agent tools confirmation。
- 数据：会话消息、timeline event、pending confirmation。
- 用户影响：页面可能无法构建；即使修复语法，Agent 流式响应和确认流程也难以测试、复用和约束 contract。

## 复现方式

1. 运行 `flutter analyze` 或任何前端构建命令。
2. 分析器会在 `frontend/lib/features/agent/agent_page.dart` 的 `?_sessionId` 位置报告语法错误。
3. 若临时修复语法后进入 `/agent`，发送消息会触发页面内部直接创建 SSE 请求并解析事件。

## 根因分析

- Agent 页面没有清晰的 controller/provider 边界，页面 widget 直接承担 API client、SSE client、业务状态机和 UI 渲染。
- SSE event、confirmation event 和 session event 没有前端 typed model，导致页面根据动态字段临时分支处理。
- `session_id` query 构造没有依据后端 router contract 做最小封装，AI 生成修改引入了显眼的语法污染。

## 关联代码

- `frontend/lib/features/agent/agent_page.dart`
- `frontend/lib/features/agent/models/agent_result.dart`
- `backend/app/routers/agent.py`
- `backend/app/services/agent/*`

## 关联文档

- `../frontend/pages/agent.md`
- `../frontend/README.md`
- `../frontend/navigation.md`
- `../backend/modules/agent.md`
- `../backend/api.md`

## 修复建议

- 最小修复：先把 `session_id` query 参数改成合法表达式，确保 `/agent` 可以通过分析和构建。
- 中期修复：新增或恢复 `AgentController` / provider，把 session 加载、SSE 连接、事件解析、确认/拒绝/停止等 intent 收敛到状态层。
- 长期修复：为 SSE event 和 confirmation event 建立 typed model，并用测试覆盖后端事件到前端 timeline state 的转换。

## 验证方式

- 自动测试：`flutter analyze`；为 Agent controller/provider 增加事件解析单元测试。
- 手动验收：进入 `/agent`，验证新建会话、发送消息、流式增量、确认/拒绝、停止 run、清空会话。
- 截图/日志：保留 Agent 页面正常打开和 SSE 消息完成的截图或日志。
