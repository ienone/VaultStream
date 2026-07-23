# Bot 配置 router 直接执行进程控制和外部同步副作用

## 状态

active

## 现象

- `backend/app/routers/bot_config.py` 在 create/update/delete/activate 配置时直接重启或停止 Telegram bot 进程。
- 同一 router 直接请求 Napcat `/get_qrcode`、直接同步 QQ group list、直接 upsert `BotChat`，并发布 `bot_sync_progress` / `bot_sync_completed` 事件。
- 测试隔离依赖 `PYTEST_CURRENT_TEST` 环境变量跳过进程副作用，说明副作用没有通过可注入 service 边界隔离。

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

- Bot 配置 CRUD、bot runtime 控制、Napcat adapter、chat 同步和事件发布混在 router 内。
- 自动同步和服务启停没有统一后台 run 记录，也没有接入用户可见自动化策略。
- 缺少 `BotConfigService` / `BotChatSyncService` 之类可注入服务，导致测试只能用环境变量绕过真实副作用。

## 关联代码

- `backend/app/routers/bot_config.py`
- `backend/app/services/telegram_bot_service.py`
- `backend/app/services/telegram_sync.py`
- `backend/app/services/bot_config_runtime.py`
- `backend/app/models.py`

## 关联文档

- `../backend/modules/accounts-auth.md`
- `../backend/modules/distribution.md`
- `../backend/modules/events-tasks.md`
- `../backend/api.md`
- `frontend-control-policy-gaps.md`

## 修复建议

- 最小修复：停止在 router 中新增 bot runtime 和外部 HTTP 逻辑，现有副作用封装为 service 方法。
- 中期修复：新增 `BotConfigService` / `BotChatSyncService`，router 只负责鉴权、请求解析、调用 service、返回 typed response。
- 长期修复：Telegram 进程控制、QQ chat sync、自动同步都应记录 background run，并明确是否需要用户策略允许或手动确认。

## 验证方式

- 自动测试：API 测试使用 fake service 验证 create/update/delete 不依赖 `PYTEST_CURRENT_TEST` 跳过副作用。
- 单元测试：覆盖 QQ sync 成功/失败、事件发布、run 记录和策略拒绝。
- 手动验收：在设置“账号与平台”中配置 Telegram/QQ bot 时，用户可见地看到哪些动作会触发外部服务或进程控制。
