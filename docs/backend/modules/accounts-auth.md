# 后端模块：账号与浏览器认证

## 文档状态

active

## 代码位置

- Router: `backend/app/routers/browser_auth.py`
- System health: `backend/app/routers/system.py`
- Service: `backend/app/services/browser_auth_service.py`
- Browser manager: `backend/app/adapters/browser/manager.py`

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

认证服务统一管理“初始化、等待扫码、已扫码、需要验证、成功、超时、失败”状态；Bilibili、微博和知乎驱动处理各自的二维码协议。小红书的扫码状态请求依赖页面运行时生成的签名、指纹和连续会话，因此由后台 Playwright 页面创建二维码、执行平台自身轮询并导出 Cookie，后端不再复刻其纯 HTTP 登录协议。登录成功后 Cookie 仍由服务统一写入配置。系统健康接口汇总平台 Cookie、认证状态、同步状态和能力状态。

该二维码流程不读取 Codex 内置浏览器的 Cookie、Local Storage 或会话存储。平台凭据只由用户主动扫码产生，并通过现有敏感配置通道保存。

## 测试

- `backend/tests/test_browser_auth_service.py`
- `backend/tests/test_api/test_browser_auth.py`
- `backend/tests/test_api/test_system.py`
- `backend/tests/test_api/test_system_extra.py`

## 与其他模块交互

- favorites-sync: 同步依赖平台登录状态。
- discovery/adapters: 部分平台解析依赖 Cookie。
- config-system: Cookie 和平台 enabled 来自系统配置。

## 对应前端

- `../../frontend/pages/settings.md`
- `../../frontend/pages/automation.md`

## API 接口

- `/api/v1/browser-auth/*`
- `GET /api/v1/platform-health`
- `POST /api/v1/platform-health/parse-test`

## 配置与策略

- Cookie、平台 enabled 和保活设置来自系统配置。
- 平台健康只报告账号/认证/解析能力，不应决定业务页面职责。

## 当前问题

- Bot 配置、运行时控制和外部同步副作用边界：`../../issues/backend-bot-config-router-side-effects.md`
- 用户控制面与后端策略缺口：`../../issues/frontend-control-policy-gaps.md`

## 尚未实现 / 计划扩展

当前账号连接控制面位于设置“账号与平台”分区，提供登录/重新登录、有效性检测、清除本地登录和二维码会话取消。是否未来迁移为独立账号中心属于后续 IA 决策，当前实现不再把这项未确定方向写成既定目标。
