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

认证服务统一管理“初始化、等待扫码、已扫码、需要验证、成功、超时、失败”状态；Bilibili、微博和知乎驱动处理各自的二维码协议。小红书的扫码状态请求依赖页面运行时生成的签名、指纹和连续会话，因此由后台 Playwright 页面创建二维码、执行平台自身轮询并导出 Cookie，后端不再复刻其纯 HTTP 登录协议。登录成功后 Cookie 仍由服务统一写入配置。`PlatformHealthService` 汇总平台 Cookie、浏览器认证、收藏认证、最近同步和保活状态，system router 只暴露现有 HTTP contract。没有 Cookie 且未启用收藏同步的平台是 `inactive`，不会仅因支持浏览器登录就产生“未配置”故障；关闭同步后，旧失败 run 也不继续污染当前健康状态。

二维码会话取消、平台本地退出和知乎指纹刷新使用统一命名 `AuthActionResponse`；成功状态与消息进入 OpenAPI contract，失败仍保留各动作原有 HTTP 状态，不把取消、退出和刷新误写成后台 run。

手动有效性检测、二维码登录完成、主动退出和 Cookie 保活会把账号状态同步到持久化消息盒子。只有“已保存凭据但校验失败”产生需要处理的账号消息；未配置、恢复有效或主动退出会关闭已有提醒。同一连续失效状态按平台去重，不因轮询重复刷屏。

Cookie 保活的三个长期调度循环随应用生命周期启动，但每次准备访问知乎、微博或小红书前都会通过 `AutomationPolicyService` 重新读取持久化的 `enable_cookie_keepalive`。关闭时该轮不创建平台检查协程、不记录成功或失败，也不更新账号通知；循环保持休眠调度，因此重新开启无需重启进程，并在下一调度点恢复。已经开始的平台检查不会被开关抢占中断。

该二维码流程不读取 Codex 内置浏览器的 Cookie、Local Storage 或会话存储。平台凭据只由用户主动扫码产生，并通过现有敏感配置通道保存。

Bot 配置 CRUD、保存后的 Telegram 进程同步、手动启停以及 Napcat 二维码/chat 同步均由可注入 service 承担；router 不再直接持久化 BotConfig，也不访问进程或外部 HTTP。自动测试注入 fake service 隔离外部副作用，不使用测试环境变量改变生产 service 行为。进程控制与 chat sync 写入统一 run；配置写响应直接引用后续 run，配置事务不会被进程失败伪装成回滚。QQ 自动同步在加入后台队列前先创建 run，避免响应与任务账本之间出现不可观察窗口。

## 测试

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

## 当前问题

- Bot 配置、运行时控制和外部同步副作用边界修复记录：`../../issues/archive/backend-bot-config-router-side-effects.md`
- 用户控制面与后端策略修复记录：`../../issues/archive/frontend-control-policy-gaps.md`

## 尚未实现 / 计划扩展

独立 `/accounts` 已提供登录/重新登录、有效性检测、清除本地登录、二维码会话取消和 Bilibili 手动凭据入口；`/accounts/:platform` 依据 `platform-health` contract 展示单账号能力状态、问题、最近同步和稳定修复步骤。桌面工具栏与移动全局工具组都有显式入口，设置不再展示平台账号对象。后端没有声明平台细粒度 OAuth scope，前端不对此作推断；真实平台人工验收仍未完成。
