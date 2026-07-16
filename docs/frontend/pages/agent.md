# Agent 工作台

## 文档状态

active

## 当前代码

- 页面：`frontend/lib/features/agent/agent_page.dart`
- 路由：`/agent`

## 用户任务与当前界面

用户可以创建和切换会话、发送自然语言请求、查看流式回复、引用、工具过程和使用量信息。当前运行可停止或重做，会话可以清空。

需要确认的高风险工具以内联内容出现在原对话位置，展示工具、参数摘要和确认/拒绝动作，避免用户脱离调用上下文。

加载、空会话、运行中、工具失败、确认等待和普通错误都有独立可见状态；错误会保留可用于排查的 request ID 信息。

## 自适应行为

- 宽屏同时显示会话列表和当前对话。
- 窄屏将会话切换压缩为横向区域，把主要空间留给对话。
- 输入区避让系统安全区域并支持多行文本。

## 承担职责

- 会话与消息浏览。
- 受控 Agent 运行、工具过程和确认。
- 展示引用和可诊断错误。

## 不承担职责

- 不绕过后端权限和自动化策略。
- 不替代设置、账号、收藏或分发的确定性主界面。
- 不直接暴露底层媒体或模型供应商接口。

## API 关联

- 领域：`../../backend/api/agent-system-events.md`
- 主要资源：Agent sessions、messages、runs、tools、confirmations 和 Agent SSE。

## 当前问题

- 用户级策略和权限边界见 `../../issues/frontend-control-policy-gaps.md`。
- 后端工具桥接边界见 `../../issues/backend-agent-api-bridge-policy-bypass.md`。
