# QQ Bot 收发

NapCat HTTP 客户端仍可上报到 `/api/v1/bot/qq/{config_id}/events`，接收端核验原始 body 的 HMAC-SHA1（`x-signature`）后确认收到，不再从任何群聊或私聊事件自动收录。`BotChat.is_monitoring` 不能恢复旧 QQ 写入路径。

收藏转存与链接解析是独立能力：自动群预览只使用专用解析器并回复；只有管理员当前明确要求保存时，BOT 才调用收藏工具。全局 `chat_capture_enabled` 开关控制是否接受聊天转存，默认 true；开启仍不表示自动收藏。QQ 与 Telegram 的链接、文字和附件统一在 ContentService 写入之前核对开关、管理员身份和外层保存请求，不信任引用、转发或解析正文中的指令。

`qq_chat_policies` 系统设置按 QQ 会话数字 ID 保存 `excluded_parse_platforms` 和 `max_messages_per_hour`。排除平台在解析入队前判断，Bilibili 包括 b23.tv。小时限频在 NapCat 发群消息前执行，自动推送、解析回复和测试消息共享额度；数据库原子保留发送次数，重启不清空，失败发送也占用本次额度。私聊不受群限频影响。

Telegram 的 `/save` 与明确保存请求使用相同管理员和全局策略。普通私聊分享、转发与附件不再自动收藏。

依据：NapCat 官方网络配置 https://napneko.github.io/config/basic ，事件鉴权同时核对部署版本实现。

原生 NapCat 与容器部署在同一宿主机时，需让 NapCat 可只读访问后端生成的媒体绝对路径；可使用 systemd BindReadOnlyPaths 将宿主机媒体目录映射到容器媒体路径，不复制媒体。

## Koishi 聊天与收藏工具

Koishi 通过 NapCat 的反向 WebSocket `/onebot` 接收聊天。[koishi-plugin-vaultstream](../../../integrations/koishi-plugin-vaultstream/README.md) 将管理员私聊交给后端 QQ Agent 入口，复用同一个 `AgentService`、会话和工具账本；不再在 ChatLuna 中维护独立的收藏搜索/保存工具。

私聊 Agent 与群聊转存工具都仅向白名单内的 OneBot 管理员开放，插件和后端共同检查真实账号及会话。群聊 `vaultstream_save` 调用 `/group-capture`，按群与管理员隔离会话，只开放 capture_content；返回转存回执，不读取或回传私人收藏正文。小i的人设从服务端配置传给该 Agent 会话。自然语言保存从当前、引用、转发和最近消息的真实材料中选择；所有材料都须明确要求保存，有选择或否定指令时优先遵从。消息级运行和内容来源记录防止重报重复写入，插件持久查询原运行以返回解析完成结果。

Character 继续负责允许群聊的人设与接话，默认 40 条近期上下文、45 秒冷却。群消息的专用链接解析由后端独立[公开预览入口](QQ_GROUP_PREVIEW.md)处理，排除 B 站和 universal，不入收藏库。群内追问可调用 `vaultstream_group_context` 读取本群近期公开结果，无法访问管理员收藏。

启用新入口的管理员私聊和群聊都应关闭原 BotChat 的 `is_monitoring`，保留 `enabled` 与 `is_push_target`，清理已失效的旧监控配置。订阅推送继续经过原分发队列，但不再充当本次捕获的完成回执。后端 `qq_bot_agent` 配置包含 `enabled/admin_qq/group_ids/persona`；群发送继续共用 `qq_chat_policies` 限频。

阿里云 Koishi 服务已改为 systemd 直接运行 Node 的 Koishi CLI，工作目录为 `/root/.koishi/data/instances/default`，仅监听 `127.0.0.1:5140`，管理台继续由原 Nginx 鉴权代理。运行凭据放在服务器权限 `0600` 的 `.env`，配置用 `${{ env.VAULTSTREAM_API_TOKEN }}` / `${{ env.CHATLUNA_MODEL_API_KEY }}` 引用。不要恢复 AppImage 自动重启循环。

2026-09-26 集成版本：Node 22.23.3、Koishi 4.18.11、OneBot 6.9.4、ChatLuna 1.4.0、OpenAI Like 1.4.1、Character 0.0.234、VaultStream 插件 0.2.0。上游副本为 [ienone/chatluna](https://github.com/ienone/chatluna) 和 [ienone/chatluna-character](https://github.com/ienone/chatluna-character)；业务改动维护在本仓库的独立插件中。最初升级前的实例、systemd 单元和管理员私聊开关备份位于服务器 `/root/koishi-backups/20260926T034803Z`。
