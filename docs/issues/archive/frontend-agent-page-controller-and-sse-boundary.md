# Agent 页面 controller 与 SSE contract 边界

## 状态

archived

## 处置说明

早期记录把 `queryParameters: {'session_id': ?_sessionId}` 误判为非法 Dart 表达式。当前 Dart 支持 null-aware map entry，且 2026-07-24 实测 `dart run build_runner build --delete-conflicting-outputs`、`flutter analyze` 和 `flutter test` 均通过，因此不存在当前构建阻断。本 issue 只继续追踪页面职责、SSE contract 和可测试性问题。

2026-09-06 已完成结构修复：新增 `AgentController` family provider 与不可变 view state，会话加载/新建/选择、SSE HTTP/鉴权、typed event 转换、confirmation、redo、stop、clear 和错误文案均移出 Widget；旧页面内请求和字符串 event switch 已删除。session、confirmation 和 SSE event 均有明确 model，SSE client factory 可在测试中替换。自动测试覆盖 session bootstrap、增量合并、confirmation 恢复/去重/拒绝和 stop。

结构问题已关闭。仓库数据库的 `GET /api/v1/ai/capabilities` 实测 Agent 为 unavailable，原因是未配置可供 Agent 使用的 LLM 密钥，因此没有伪造真实模型人工 SSE 通过。该外部配置限制不再作为页面继续保留旧架构的理由，也不能据自动测试宣称真实模型已可用。

## 原现象

- 同一页面文件约 900 行，直接负责会话列表加载、新建/选择会话、SSE HTTP 连接、事件解析、确认决策、redo、stop、clear、timeline 本地状态和错误展示。
- 页面通过 `apiClientProvider` 和 `http.Client` 直接拼接 `/agent/sse` 请求，并用动态 `Map<String, dynamic>` 和字符串分支解释后端事件。
- `agent_result.dart` 已为部分结果建立 model，但 SSE 增量事件仍主要在 Widget 内按字符串类型分支转换为本地 timeline 状态。

## 影响范围

- 页面：`/agent` Agent 工作台。
- 后端模块：Agent SSE、Agent session、Agent tools confirmation。
- 数据：会话消息、timeline event、pending confirmation。
- 用户影响：页面当前可以构建，但流式响应、确认和会话状态难以独立测试、复用和约束；协议变化容易直接破坏 UI。

## 复现方式

1. 检查 `frontend/lib/features/agent/agent_page.dart` 中的 session CRUD、`http.Client`、SSE 行解析、event type switch、confirmation、redo、stop 和 clear 方法。
2. 进入 `/agent` 发送消息，可观察这些流程都由 `_AgentPageState` 直接编排。
3. 当前 `flutter analyze` 不会报告 `?_sessionId` 语法错误；该写法是合法的 null-aware map entry。

## 根因分析

- Agent 页面没有清晰的 controller/provider 边界，页面 widget 直接承担 API client、SSE client、业务状态机和 UI 渲染。
- SSE event、confirmation event 和 session event 没有前端 typed model，导致页面根据动态字段临时分支处理。
- `/agent/sse` 的请求构造、鉴权和事件转换没有进入可复用 client/controller contract。

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

- 第一阶段：新增或恢复 `AgentController` / provider，把 session 加载、SSE 连接、事件解析、确认/拒绝/停止等 intent 收敛到状态层。
- 第二阶段：为 SSE event、confirmation event 和 session event 建立 typed model，并用测试覆盖后端事件到前端 timeline state 的转换。
- 收敛完成后删除 Widget 内旧请求和字符串分支，不保留双路径。

## 验证方式

- `flutter analyze --no-pub` 无问题；完整 `flutter test --no-pub` 为 **133 passed**。
- `agent_controller_test.dart` 与 `agent_confirmation_recovery_test.dart` 覆盖 controller/provider、SSE 增量合并、确认恢复/拒绝/去重和停止。
- 仓库数据库能力读取确认真实 Agent 模型当前不可用；真实模型、截图和原生端人工验收未执行，不能由本 issue 的结构关闭状态外推。
