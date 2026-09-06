# Bot 配置 router 直接执行进程控制和外部同步副作用

## 状态

archived

## 现象

- create/update/delete/activate 配置后仍会按现有产品行为同步 Telegram bot 进程，启用 QQ 配置后仍会安排 chat 自动同步；这些动作现在已写入统一 run，失败和手动成功会进入现有消息盒子。
- 进程控制、Napcat `/get_qrcode`、QQ group list 同步、`BotChat` upsert 和同步事件已经移入 `backend/app/services/bot_config_service.py`，router 只调用可注入 service。
- 测试通过 FastAPI dependency override 注入无外部副作用的 fake service，不再读取 `PYTEST_CURRENT_TEST` 决定业务行为。

## 影响范围

- 后端模块：accounts-auth、distribution、events-tasks、config-system。
- 前端页面：设置中的账号与平台分区、自动化健康矩阵。
- 数据：BotConfig、BotChat、分发目标关联、bot 同步事件。
- 用户影响：保存配置可能隐式重启进程或访问外部服务；这些动作没有统一 run 记录、策略检查和可见确认。

## 复现方式

1. 打开 `backend/app/routers/bot_config.py`。
2. 查看 `create_bot_config()`、`update_bot_config()`、`delete_bot_config()`、`start_telegram_service()`、`get_napcat_qr_code()`、`sync_bot_config_chats()`。
3. 观察 router 内部直接执行进程控制、HTTP 请求、数据库 upsert 和事件发布。

## 根因分析

- Bot 配置 CRUD、bot runtime 控制、Napcat adapter、chat 同步和事件发布均已拆到 service 边界；router 只保留鉴权、request/response contract、依赖注入和 HTTP 错误映射。
- 自动同步、手动 chat sync 和服务启停已写入统一后台 run；配置 enabled/primary 与显式手动按钮继续作为现有用户控制面，没有新增缺乏产品依据的平行开关。
- 配置写入先独立提交，随后运行时同步以 `trigger=config_change` 的单独 run 结算：配置保存成功不因进程失败回滚，运行时失败通过任务详情与消息盒子显式暴露。
- 手动启停/重启返回命名 `BotRuntimeActionResponse` 和稳定 `run_id`；嵌套 restart 的 start/stop 阶段失败会把整个 run 标为失败，不再把外层 `restarted` 冒充成功。

## 关联代码

- `backend/app/routers/bot_config.py`
- `backend/app/services/bot_config_service.py`
- `backend/app/services/telegram_bot_service.py`
- `backend/app/services/telegram_sync.py`
- `backend/app/services/bot_config_runtime.py`
- `backend/app/models.py`

## 关联文档

- `../backend/modules/accounts-auth.md`
- `../backend/modules/distribution.md`
- `../backend/modules/events-tasks.md`
- `../backend/api.md`
- `archive/frontend-control-policy-gaps.md`

## 修复建议

- 已完成：停止在 router 中保留 bot runtime 和外部 HTTP 逻辑，现有副作用封装为 `TelegramBotRuntimeService` / `BotChatSyncService`。
- 已完成：Bot 配置 CRUD 与“配置已保存、运行时同步失败”的响应语义已收敛到 `BotConfigService`，router 只负责鉴权、请求解析、调用 service、返回 typed response。
- 已完成：Telegram 进程控制、QQ/Telegram chat sync 和自动同步记录 background run；手动动作直接受用户点击控制，配置变更同步受对应 enabled/primary 配置控制。
- 已完成：配置 create/update/activate/delete 使用命名响应并直接引用随后的 runtime/chat-sync run；QQ 自动同步在调度后台任务前创建 run。前端不再把所有保存结果一律提示为“正在启动”，而是区分已完成、已提交和配置已保存但运行时失败。

## 验证方式

- 自动测试：API 测试使用 fake service 验证 create/update/delete 不依赖 `PYTEST_CURRENT_TEST` 跳过副作用。
- 单元测试：已覆盖 QQ sync 的 HTTP、持久化、事件发布和 run 记录，以及无主配置时的 Telegram stop、直接进程失败与 restart 嵌套阶段失败。
- 手动验收：在设置“账号与平台”中配置 Telegram/QQ bot 时，用户可见地看到哪些动作会触发外部服务或进程控制。
