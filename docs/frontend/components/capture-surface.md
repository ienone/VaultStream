# 统一捕获 Surface

## 文档状态

active

## 当前代码

- 组件：`frontend/lib/features/collection/widgets/dialogs/add_content_dialog.dart`
- 输入模型：`frontend/lib/features/collection/models/capture_draft.dart`
- 写控制层：`frontend/lib/features/collection/providers/content_actions_controller.dart`
- 系统分享接收：`frontend/lib/features/share_receiver/share_receiver_service.dart`
- Telegram 显式捕获：`backend/app/bot/commands.py::save_command`、`handle_natural_capture_message`

## 当前职责

应用内“保存内容”和操作系统分享进入同一个 surface。组件根据输入预选链接、原始文本或文件，但允许用户在提交前切换类型、补充标题、保存说明、标签和敏感标记。

- 链接使用 `/shares`，保留分享附带文本作为来源说明，并在解析队列暂不可用时表达“已保存、待处理”。
- 原始文本使用 `/captures/text`，不伪造外部 URL。
- 一个或多个文件使用 `/captures/files`；同一次分享中的媒体不会只取第一项或拆成无关联记录。
- 系统分享使用 `system_share` 来源并保存接收时间；取消或提交后统一清除当前 intent，避免重复弹出。
- Telegram Bot 的显式 `/save` 复用 `/shares`、`/captures/text` 与 `/captures/files`，可直接接收链接/文字，也可回复带文字、链接、图片、文件、音视频或语音的消息；私聊中以“帮我保存 …”“收藏：…”等明确前缀表达的请求复用同一处理器。来源保存为 `telegram_bot`，并保留 chat/message/forwarded/attachment type 的最小上下文。

主输入只提供链接、文本、文件三类。附加信息默认折叠（已有草稿时展开），不提供预设快捷标签；切换类型保留当前文本和说明。全局保存入口复用此组件，收藏页不再复制添加 FAB。

组件只调用内容写控制层，不在 Widget 内解析 HTTP 响应或复制错误判断。

## 自适应行为

- Compact、Medium 和短横屏使用可滚动 bottom sheet，避让键盘和系统安全区。
- Expanded 及以上且高度充足时使用限宽 dialog；表单不会随超宽窗口拉伸。
- 所有形态共享同一输入状态和提交 contract，不保留第二套系统分享表单。Bottom sheet 的最大高度在当前布局中计算，横屏打开后转竖屏不会沿用旧高度；旋转不重新创建输入表单。

## 当前边界

保存说明会作为来源上下文保留，但当前不会冒充已完成的 Agent 指令理解。Bot `/save` 和私聊中的严格前缀请求是明确保存意图；疑问句、其他普通聊天和群聊自然语言不会自动归档，已监控群聊仍只进入发现缓冲。当前一次请求保存一条消息中的一个 Telegram 附件，跨消息 media group 的批量合并仍未实现。模板判断、不确定意图确认、合并建议和高成本媒体保留决策仍需后续接入 Agent/规则确认；OCR、转写和转码也不属于上传同步结果。
