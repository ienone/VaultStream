# Agent 工作台

## 文档状态

active

## 当前代码

- 页面：`frontend/lib/features/agent/agent_page.dart`
- 路由：`/agent`
- 后端：`/api/v1/agent/*`

## 当前界面内容

- 页面整体是 `Scaffold` + 普通 `AppBar`，标题为“Agent 工作台”。AppBar 右侧有三个动作：重做上一步、刷新/停止当前运行、清空当前会话；运行中时刷新按钮切换为停止语义。
- 页面通过宽度约 920px 的断点切换布局。宽屏使用 `Row`：左侧固定约 300px 会话栏，中间 `VerticalDivider`，右侧 `Expanded` 对话工作区；窄屏使用 `Column`：顶部约 92px 高的紧凑会话横栏，下方是对话工作区。

### 会话区域

- 宽屏会话栏 `_SessionPane` 使用纵向 `Column`：顶部是“新会话” `FilledButton.icon`，下方 `ListView.builder` 渲染会话列表。
- 每个会话 tile 显示标题、状态、待确认数量等信息；当前会话会高亮。
- 窄屏紧凑会话栏使用横向 `ListView.separated`：第一个是“新会话” `ActionChip`，后续会话以 `ChoiceChip` 展示，便于在手机宽度下横向滑动切换。

### 对话工作区

- 对话工作区 `_ConversationPane` 是纵向 `Column`：上方 `Expanded` 显示空态或时间线，中间可显示内联错误提示，底部是带 `SafeArea` 的输入区。
- 空态工作台居中展示 Agent 图标和说明，并用 `Wrap` 排列三个预设 `ActionChip`，例如检索内容、列出推送群组、创建规则。
- 消息时间线使用 `ListView.builder`。用户消息靠右，助手消息靠左；气泡最大宽度受限，内部用图标 + 文本内容的 `Row` 组织。
- 工具调用和工具结果以带边框的事件卡展示，标题行显示工具名和状态，正文可展示 JSON 或摘要；引用内容用最多 5 个 `InputChip` 呈现，chip tooltip 显示来源信息。
- 高风险工具确认不是弹窗，而是时间线中的 `_ConfirmationTile`。它使用强调色背景，展示工具名、summary、args JSON，并用 `Wrap` 放置“确认”和“拒绝”按钮。
- 运行过程中的 context summary、usage、error、final 等 SSE 事件会转成 notice、工具事件、助手增量消息或内联错误；页面支持流式追加助手回复。

### 输入区与运行控制

- 底部输入区由 `TextField` 和 `FilledButton.icon` 组成。输入框支持 1 到 5 行，多行时自动增高；发送按钮在有内容且未运行时可用。
- 运行中可以通过 AppBar 或输入区按钮停止当前 run；重做会重新执行上一步；清空会清空当前会话消息。
- 错误信息会按后端 `error_code` 映射为友好的中文提示，并附带 request ID 短码，显示在对话区上方的错误条中。

### 弹出界面

- 当前 Agent 页面没有独立 modal 弹窗作为主交互；高风险确认以内联卡片形式出现在时间线中，避免脱离上下文。
- 外部链接、引用内容和工具动作后续可扩展为跳转收藏详情、规则页或账号/设置页，但当前主要以 chip 和工具事件卡呈现。

## 承担职责

- 让用户通过 Agent 查询内容、触发受控工具和查看引用。
- 展示 Agent 会话历史和运行状态。
- 对需要确认的工具调用提供用户确认入口。

## 不承担职责

- 不绕过用户级自动化策略。
- 不直接替代账号中心、设置页或分发页面。
- 不直接暴露二进制媒体接口。

## 与其他页面交互

- Agent 工具可能读取内容、标签、统计、规则或触发收藏导入。
- 高风险动作必须经过确认，并应受后台策略约束。

## 后端/API 关联

- 读取接口：`GET /api/v1/agent/sessions`、`GET /api/v1/agent/sessions/{session_id}/messages`、`GET /api/v1/agent/tools`。
- 写入接口：`POST /api/v1/agent/run`、`POST /api/v1/agent/confirmations/{confirmation_id}/decide`、`POST /api/v1/agent/tools/{tool_name}/invoke`。
- 后台任务：Agent run 和 tool call 由后端 Agent service 记录。

## 尚未实现 / 计划扩展

无本页单独计划；Agent 用户级策略和权限边界以 `../../issues/frontend-control-policy-gaps.md` 为准。
