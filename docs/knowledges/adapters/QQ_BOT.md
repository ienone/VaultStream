# QQ Bot 收发

NapCat HTTP 客户端上报到 `/api/v1/bot/qq/{config_id}/events`，token 与对应 BotConfig 的 `napcat_access_token` 一致。接收端验证原始 body 的 HMAC-SHA1（`x-signature`），忽略自身消息及非消息事件。只处理 enabled 且 is_monitoring 的 BotChat；群 chat_id 使用数字，私聊使用 `private:QQ号`。

文字链接、JSON 分享卡片中的跳转链接、合并转发与引用中的文字链接复用 ContentService 和解析队列。私聊无链接文字保存到收藏库；纯图片、视频等 QQ 附件尚未接入捕获。群内解析完成后复用分发器回复图文和媒体，私聊先确认收录，结果使用配置的全量规则推送。链接重复使用既有内容，同消息重报通过 ContentSource 上下文判断。

`qq_chat_policies` 系统设置按 QQ 会话数字 ID 保存 `excluded_parse_platforms` 和 `max_messages_per_hour`。排除平台在解析入队前判断，Bilibili 包括 b23.tv。小时限频在 NapCat 发群消息前执行，自动推送、解析回复和测试消息共享额度；数据库原子保留发送次数，重启不清空，失败发送也占用本次额度。私聊不受群限频影响。

Telegram 私聊直接发送链接、转发消息或附件复用原有 `/save` 捕获及权限检查，不需要额外命令。

依据：NapCat 官方网络配置 https://napneko.github.io/config/basic ，事件鉴权同时核对部署版本实现。

原生 NapCat 与容器部署在同一宿主机时，需让 NapCat 可只读访问后端生成的媒体绝对路径；可使用 systemd BindReadOnlyPaths 将宿主机媒体目录映射到容器媒体路径，不复制媒体。
