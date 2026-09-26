# koishi-plugin-vaultstream

QQ 是 VaultStream Agent 的消息入口。管理员私聊由同一个后端 Agent 保存会话、理解请求、调用工具；Character 保留群聊人设，并可读取本群刚解析的公开材料。插件不维护另一套收藏、解析器或 Agent 工具执行逻辑。

需要 Node.js 20+、Koishi 4.18.11+、ChatLuna 1.4.x。

```sh
npm install --package-lock=false
npm run typecheck
npm run build
```

安装目录、构建产物、打包文件和 package-lock.json 不进入 Git。

## 配置

- `apiBaseUrl`：VaultStream 地址，包含 `/api/v1`。
- `apiToken`：只保存在服务端的 API Token。
- `botConfigId`：对应的 QQ Bot 配置 ID。
- `adminQQ`：可进入私聊 Agent 的 QQ 号数组，默认不开放。
- `groupIds`：自动专用解析的群号数组，默认不开放。

后端 `qq_bot_agent` 同时设置 `enabled`、`admin_qq`、`group_ids` 和可选 `persona`，插件白名单不能绕过后端权限。私聊仅接受 OneBot、真实管理员账号及直接私聊；临时群私聊不进入私人 Agent。配置凭据不要写入 Git。

## 私聊

直接说“把下面第二个链接存起来”“保存引用的这段文字”“查一下之前收藏的音乐文章”。插件按真实 QQ 消息保留文本、链接出现顺序、引用、转发和可下载附件，Agent 从材料引用中选择保存目标。任何普通聊天、链接分享、转发和附件都不自动保存；只有当前管理员明确要求转存时才调用收藏工具，按指定范围保存。

原来在 ChatLuna 中独立注册的搜索、阅读、固定句式保存工具已移除。相应工作由 VaultStream Agent 的正式工具完成。管理员明确要求的消息材料收藏仍受全局 `chat_capture_enabled` 控制；其他写入和外发继续通过后端确认；唯一待确认项可直接回复“确认”或“取消”，多项待确认需进入对应 VaultStream 会话选择。

后端按 Bot、管理员、消息 ID 记录确定性运行，重复上报不重放写操作。保存和解析分开显示。插件在 `data/vaultstream/receipts-<botConfigId>.json` 保存不含正文的待完成回执，恢复后查询原运行，不重新保存。发送结果未知不自动重发。后台解析队列不可用会明确显示已收藏、解析待处理。

QQ 文件取址遵循 [NapCat 文件接口](https://napneko.github.io/develop/file)。当前支持 QQ 提供 HTTP(S) 下载地址的图片、音视频和文件；普通文件按会话使用 `get_private_file_url` 或 `get_group_file_url` 取址；群文件参数与返回值核对 [NapCat 官方实现](https://github.com/NapNeko/NapCatQQ/blob/main/packages/napcat-onebot/action/file/GetGroupFileUrl.ts)。只有本地路径而无直链的附件会明确报告无法下载。后端按官方 QQ CDN、地址及大小检查原件，复用既有文件捕获，不宣称已完成 OCR 或语音转写。

## 群聊

自动将消息中的链接交给后端 `/bot/qq/{config_id}/preview`。后端只使用实际支持的专用解析器，排除 B 站、普通网页和未知短链；不读取私人收藏，也不写入收藏库。支持范围见 [群聊解析契约](../../docs/knowledges/adapters/QQ_GROUP_PREVIEW.md)。

每项以正文和最多一张图片组成一条消息，发送前占用原 QQ 群共享限频额度。重复消息不重复解析或发送；发送状态不确定时不重发。没有命中专用解析的消息继续交给普通群聊。

`vaultstream_group_context` 仅向允许群聊开放，返回本群最近半小时最多八次公开解析的临时材料，便于“小i，你怎么看刚才那篇”这类追问。它无法搜索或读取私人收藏。工具按 [ChatLuna 工具接口](https://chatluna.chat/development/connect-to-core-services/model-tool.html) 注册，每次执行重新校验当前会话。

`vaultstream_save` 是独立的群聊转存工具，只向管理员开放。聊天模型根据当前明确保存请求调用，身份与材料从真实 QQ 消息取得；后端再次核验全局开关和外层保存意图，复用同一 Agent 的 capture_content。群聊运行与私聊分开，不能搜索或读取私人收藏；预览结果本身不会调用此工具。

## 切换与验证

启用此入口后，关闭对应管理员私聊及群聊原 NapCat HTTP `BotChat.is_monitoring`，保留订阅发送能力，避免配置误导。所有需要解析的群必须同时加入插件与后端白名单，不能只迁移一个群。后端 HTTP 入口已停止所有自动收录，遗留或重新打开监控也不会恢复自动收藏。群解析完成不触发收藏后的自动分发。

类型检查和构建只证明插件边界；后端离线流程、真实模型调用、实际 QQ 收发应分别报告。当前实现不承诺网络发送 exactly-once；不携带长期测试套件。
