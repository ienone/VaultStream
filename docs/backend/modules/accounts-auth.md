# 后端模块：账号与浏览器认证

## 文档状态

active

## 代码位置

- Router: `backend/app/routers/browser_auth.py`
- System health: `backend/app/routers/system.py`
- Service: `backend/app/services/browser_auth_service.py`
- Platform health service: `backend/app/services/platform_health_service.py`
- Browser manager: `backend/app/adapters/browser/manager.py`
- Bot config router: `backend/app/routers/bot_config.py`
- Bot runtime/chat sync service: `backend/app/services/bot_config_service.py`

## 功能

- 检查平台 Cookie 是否存在和有效。
- 通过各平台二维码协议完成登录、重新登录和会话取消。
- 提供平台健康状态。
- 支持 Cookie 保活状态展示。

## 不承担职责

- 不执行收藏同步业务逻辑。
- 不执行分发推送。
- 不替代系统设置模块。

## 实现逻辑

浏览器管理器保留现有 WebKit 认证/读取实例，并为知乎公开页面按需创建 Chromium；二者复用后台事件循环，应用关闭时一并释放。公开页面使用临时 context，不读取或回写账号 Cookie；不改变扫码登录和保活语义。

认证服务统一管理“初始化、等待扫码、已扫码、需要验证、成功、超时、失败”状态；Bilibili、微博和知乎驱动处理各自的二维码协议。小红书的扫码状态请求依赖页面运行时生成的签名、指纹和连续会话，因此由后台 Playwright 页面创建二维码、执行平台自身轮询并导出 Cookie，后端不再复刻其纯 HTTP 登录协议。登录成功后 Cookie 仍由服务统一写入配置。`PlatformHealthService` 汇总平台 Cookie、浏览器认证、收藏认证、最近同步和保活状态，system router 只暴露现有 HTTP contract。没有 Cookie 且未启用收藏同步的平台是 `inactive`，不会仅因支持浏览器登录就产生“未配置”故障；关闭同步后，旧失败 run 也不继续污染当前健康状态。

二维码会话取消、平台本地退出和知乎指纹刷新使用统一命名 `AuthActionResponse`；成功状态与消息进入 OpenAPI contract，失败仍保留各动作原有 HTTP 状态，不把取消、退出和刷新误写成后台 run。

手动有效性检测、二维码登录完成、主动退出和 Cookie 保活会把账号状态同步到持久化消息盒子。只有“已保存凭据但校验失败”产生需要处理的账号消息；未配置、恢复有效或主动退出会关闭已有提醒。同一连续失效状态按平台去重，不因轮询重复刷屏。

Cookie 保活的三个长期调度循环随应用生命周期启动，但每次准备访问知乎、微博或小红书前都会通过 `AutomationPolicyService` 重新读取持久化的 `enable_cookie_keepalive`。关闭时该轮不创建平台检查协程、不记录成功或失败，也不更新账号通知；循环保持休眠调度，因此重新开启无需重启进程，并在下一调度点恢复。已经开始的平台检查不会被开关抢占中断。

该二维码流程不读取 Codex 内置浏览器的 Cookie、Local Storage 或会话存储。平台凭据只由用户主动扫码产生，并通过现有敏感配置通道保存。

同平台再次发起登录会取消并释放旧二维码会话；清除登录先等待该平台二维码任务取消，再删除持久凭据，避免晚到扫码结果恢复已退出账号。二维码只有在 Cookie 已保存后才报告 success；结束后清理会话内的 Cookie 副本。隔离验证使用实际配置数据库和替换的二维码协议，包含新服务实例读取已保存登录。

知乎浏览器 Cookie 刷新，以及知乎/小红书收藏响应中的会话更新，通过 SystemRepository 的条件更新提交：只有请求使用的原登录仍是数据库当前值才替换。退出、重新登录或并发更新后，迟到刷新结果丢弃；不创建另一个 Cookie 仓库，也不将仅环境变量提供的 Cookie 自动迁入数据库。此验证证明本地持久化与竞态约束，不保证平台不会主动使登录失效。

Bot 配置 CRUD、保存后的 Telegram 进程同步、手动启停以及 Napcat 二维码/chat 同步均由可注入 service 承担；router 不再直接持久化 BotConfig，也不访问进程或外部 HTTP。自动测试注入 fake service 隔离外部副作用，不使用测试环境变量改变生产 service 行为。进程控制与 chat sync 写入统一 run；配置写响应直接引用后续 run，配置事务不会被进程失败伪装成回滚。QQ 自动同步在加入后台队列前先创建 run，避免响应与任务账本之间出现不可观察窗口。

## 测试

最近收藏同步只关联显式指定该平台的任务，或 results 中确实包含该平台的全平台任务。空全平台任务及无 scope 的历史记录不证明任何平台执行过同步，不显示为该平台的最近成功。

账号列表、详情和健康判断使用 last_run_status 的平台结果，整批 last_run 仍保留原状态和任务链接。部分导入失败标记为部分失败，运行时禁用导致 skipped 显示已跳过，不冒充同步成功，也不让其他平台的失败污染本平台。

长期回归与临时验收边界见 [验证策略](../testing.md)。本模块其余行为在变更时针对性验收，不保留逐方法测试清单。

## 与其他模块交互

- favorites-sync: 同步依赖平台登录状态。
- discovery/adapters: 部分平台解析依赖 Cookie。
- config-system: Cookie 和平台 enabled 来自系统配置。
- notification-inbox: 持久化平台登录失效提醒并跳转账号中心。

## 对应前端

- `../../frontend/pages/accounts.md`
- `../../frontend/pages/settings.md`（仅服务器连接配置）
- `../../frontend/pages/automation.md`

## API 接口

- `/api/v1/browser-auth/*`
- `GET /api/v1/platform-health`
- `POST /api/v1/platform-health/parse-test`

## 配置与策略

- Cookie、平台 enabled 和保活设置来自系统配置。
- 平台健康只报告账号/认证/解析能力，不应决定业务页面职责。

## 历史决策

- [已关闭问题的历史决策](../../issues/archive/README.md)。

## 尚未实现 / 计划扩展

独立 `/accounts` 已提供登录/重新登录、有效性检测、清除本地登录、二维码会话取消和 Bilibili 手动凭据入口；`/accounts/:platform` 依据 `platform-health` contract 展示单账号能力状态、问题、最近同步和稳定修复步骤。桌面工具栏与移动全局工具组都有显式入口，设置不再展示平台账号对象。后端没有声明平台细粒度 OAuth scope，前端不对此作推断；真实平台人工验收仍未完成。

## Telegram 用户账号

原生 MTProto 用户同步与 Telegram Bot 独立。应用凭据使用 TELEGRAM_API_ID／TELEGRAM_API_HASH，已授权会话由 TELEGRAM_SESSION_PATH 指定；后台不会自动请求验证码或创建登录。状态接口只报告配置、会话文件存在和任务运行状态，文件存在不表示认证已通过。

`GET /api/v1/telegram-account/status`、`PUT /api/v1/telegram-account/options`（channels_enabled、saved_enabled）与 `POST /api/v1/telegram-account/sync` 均需要 API Token。同步受理返回 202 和 run_id；未配置、关闭或正在同步返回 409。只有周期任务 leader 使用账号会话。Flutter 控制面已接入两项开关及手动同步，显式二维码登录及两步验证已接入，尚待真实账号验收。关闭任一同步项会取消并等待当前批次退出；开关修改与手动启动使用同一锁，只有 leader 处理这两种操作。

原生登录与同步共用客户端配置，但仅登录开启 updates 以等待扫码确认。用户显式开启一次登录，二维码过期或失败后需主动重试；服务器不自动请求短信或验证码。登录会话只驻留内存，授权由 Telethon 保存到权限 600 的会话文件，两步验证密码不持久化。关闭弹窗取消登录、服务关闭断开连接，最长五分钟自动结束；旧 login_id 不能取消新会话。
