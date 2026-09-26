# koishi-plugin-vaultstream

ChatLuna 的独立 VaultStream 业务插件。ChatLuna 负责对话；本插件仅调用现有 `/search/unified`、`/contents/{id}`、`/shares`，不调用 `/agent/run`，不维护另一份内容库、索引或推送队列。

需要 Node.js 20+、Koishi 4.18.11+、ChatLuna 1.4.x。注册方式及当前会话传递依据 [ChatLuna 官方工具文档](https://chatluna.chat/development/connect-to-core-services/model-tool.html)，并核对正式 npm 1.4.0 发布包。

## 安装与配置

```sh
npm install
npm run build
```

在 Koishi 项目安装此本地包并启用 `vaultstream`。配置：

- `apiBaseUrl`：正式 API 地址，含 `/api/v1`，例如 `https://vaultstream.example/api/v1`。
- `apiToken`：后端全局 API Token，配置项使用 secret，不能写入仓库。
- `adminQQ`：明确授权的 QQ 号字符串数组。默认 `[]`，任何人均不能访问。
- `botConfigId`：VaultStream 中对应 QQ Bot 的配置 ID。

仅接受 OneBot 平台、真实管理员 QQ 号、私聊三项同时成立的会话。群聊和其他平台一律不能读取或保存。每次工具执行从 Runnable 的 `configurable.session` 重新验权，不复用创建工具时的会话。

## 使用

- `vaultstream.search 关键词`：每页 5 条；`-p 2` 读取第二页。仅关键词检索，不调用 embedding。
- `vaultstream.read 123`：读取最多 6000 字符原文；按返回的 `-o` 偏移继续。
- `vaultstream.save https://example.com/article`：保存当前消息中的单个链接，明确返回内容 ID。

ChatLuna Agent 模式可使用 `vaultstream_search`、`vaultstream_read`。`vaultstream_save` 不接受 URL 参数，仅当**当前原始消息**完整为 `保存 URL` 或 `收藏 URL` 时执行；普通对话、历史链接和模型改写的链接不能触发保存。确定性保存命令不依赖模型。禁止在模型命令执行插件中绕过这些入口。

保存带固定 `source=qq_bot` 及真实 Bot、用户、私聊、消息上下文。`503 parse_queue_unavailable` 表达“已保存，解析待处理”；网络结果未知不自动重试。同一进程内最近 200 条保存消息复用同一结果。重启后不保证消息幂等：后端 URL 去重只复用内容，重复提交仍可能增加来源记录。

启用插件收录的私聊，应关闭 VaultStream 同一会话原来的自动监控收录，避免一条消息被两个入口处理。订阅和内容推送继续使用 VaultStream 原队列。

## 验证边界

`npm run typecheck` 与 `npm run build` 验证类型和构建。真实 QQ 触发、模型选择工具以及保存后的解析/分发，需要在明确授权账号下单独验收；本包不携带长期测试套件。
