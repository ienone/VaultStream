# QQ Bot 收发

NapCat HTTP 客户端上报到 `/api/v1/bot/qq/{config_id}/events`，token 与对应 BotConfig 的 `napcat_access_token` 一致。接收端验证原始 body 的 HMAC-SHA1（`x-signature`），忽略自身消息、非消息事件和所有群消息。旧收录仅处理 enabled 且 is_monitoring 的私聊 BotChat，chat_id 使用 `private:QQ号`；群聊即使遗留监控开关也不能从 HTTP 入口入库。

旧私聊收录中的文字链接、JSON 分享卡片跳转链接、合并转发与引用文字链接复用 ContentService 和解析队列。该旧入口会保存无链接文字，不处理纯附件，因此管理员私聊应关闭旧监控并使用下述 Agent 入口。链接重复使用既有内容，同消息重报通过 ContentSource 上下文判断。原群聊“先入库、等待解析后回群”的处理已移除，群聊只使用 Koishi 公开预览。

`qq_chat_policies` 系统设置按 QQ 会话数字 ID 保存 `excluded_parse_platforms` 和 `max_messages_per_hour`。排除平台在解析入队前判断，Bilibili 包括 b23.tv。小时限频在 NapCat 发群消息前执行，自动推送、解析回复和测试消息共享额度；数据库原子保留发送次数，重启不清空，失败发送也占用本次额度。私聊不受群限频影响。

Telegram 私聊直接发送链接、转发消息或附件复用原有 `/save` 捕获及权限检查，不需要额外命令。

依据：NapCat 官方网络配置 https://napneko.github.io/config/basic ，事件鉴权同时核对部署版本实现。

原生 NapCat 与容器部署在同一宿主机时，需让 NapCat 可只读访问后端生成的媒体绝对路径；可使用 systemd BindReadOnlyPaths 将宿主机媒体目录映射到容器媒体路径，不复制媒体。

## Koishi 聊天与收藏工具

Koishi 通过 NapCat 的反向 WebSocket `/onebot` 接收聊天。[koishi-plugin-vaultstream](../../../integrations/koishi-plugin-vaultstream/README.md) 将管理员私聊交给后端 QQ Agent 入口，复用同一个 `AgentService`、会话和工具账本；不再在 ChatLuna 中维护独立的收藏搜索/保存工具。

收藏工具仅向白名单内的 OneBot 管理员私聊开放，插件和后端共同检查真实账号及会话。小i的人设从服务端配置传给该 Agent 会话。自然语言保存从当前、引用、转发和最近消息的真实材料中选择；独立分享自动收藏，普通文字须明确要求保存，有选择或否定指令时优先遵从。消息级运行和内容来源记录防止重报重复写入，插件持久查询原运行以返回解析完成结果。

Character 继续负责允许群聊的人设与接话，默认 40 条近期上下文、45 秒冷却。群消息的专用链接解析由后端独立[公开预览入口](QQ_GROUP_PREVIEW.md)处理，排除 B 站和 universal，不入收藏库。群内追问可调用 `vaultstream_group_context` 读取本群近期公开结果，无法访问管理员收藏。

启用新入口的管理员私聊和群聊都应关闭原 BotChat 的 `is_monitoring`，保留 `enabled` 与 `is_push_target`，避免 HTTP 与 Koishi 双入口。订阅推送继续经过原分发队列，但不再充当本次捕获的完成回执。后端 `qq_bot_agent` 配置包含 `enabled/admin_qq/group_ids/persona`；群发送继续共用 `qq_chat_policies` 限频。

阿里云 Koishi 服务已改为 systemd 直接运行 Node 的 Koishi CLI，工作目录为 `/root/.koishi/data/instances/default`，仅监听 `127.0.0.1:5140`，管理台继续由原 Nginx 鉴权代理。运行凭据放在服务器权限 `0600` 的 `.env`，配置用 `${{ env.VAULTSTREAM_API_TOKEN }}` / `${{ env.CHATLUNA_MODEL_API_KEY }}` 引用。不要恢复 AppImage 自动重启循环。

2026-09-26 集成版本：Node 22.23.3、Koishi 4.18.11、OneBot 6.9.4、ChatLuna 1.4.0、OpenAI Like 1.4.1、Character 0.0.234、VaultStream 插件 0.2.0。上游副本为 [ienone/chatluna](https://github.com/ienone/chatluna) 和 [ienone/chatluna-character](https://github.com/ienone/chatluna-character)；业务改动维护在本仓库的独立插件中。最初升级前的实例、systemd 单元和管理员私聊开关备份位于服务器 `/root/koishi-backups/20260926T034803Z`。
