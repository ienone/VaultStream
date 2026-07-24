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
- 通过浏览器流程完成登录。
- 提供平台健康状态。
- 支持 Cookie 保活状态展示。

## 不承担职责

- 不执行收藏同步业务逻辑。
- 不执行分发推送。
- 不替代系统设置模块。

## 实现逻辑

浏览器认证服务启动受控浏览器会话，平台 Cookie 写入配置或运行时状态。系统健康接口汇总平台 Cookie、认证状态、同步状态和能力状态。

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

当前账号摘要和部分低频连接参数仍位于设置“账号与平台”分区。目标设计是按前端 IA 新建独立账号中心，集中承接连接、检测、解绑、权限和修复流程；设置只保留应用与系统配置。选择账号中心切片时，再核对当前认证 API、平台状态和控制策略。
