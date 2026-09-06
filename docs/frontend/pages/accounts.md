# 账号中心

## 文档状态

active

## 当前代码

- 页面：`frontend/lib/features/accounts/account_center_page.dart`
- 详情：`frontend/lib/features/accounts/account_detail_page.dart`
- 平台账号面板：`frontend/lib/features/settings/presentation/tabs/connection_tab.dart`
- 路由：`/accounts`、`/accounts/:platform`

## 用户任务与当前界面

账号中心集中展示后端 `platform-health` 返回的平台账号状态。用户可以区分未保存凭据、已保存登录、登录失效、同步未启用和同步认证失败，并执行扫码连接、重新登录、有效性检测或清除 VaultStream 保存的登录信息。Bilibili 的手动高级凭据也只保留在账号中心。

点击平台账号进入独立详情。详情只展示 `platform-health` 明确返回的本地登录信息、浏览器登录支持、收藏同步支持/启用/可用/认证状态、当前问题和最近同步；不把这些能力字段包装成平台未声明的 OAuth 权限。最近同步可进入统一任务结果，账号动作继续复用 browser-auth 控制层。

账号列表提供 Cookie 保活策略；

账号中心不读取浏览器 Cookie 或密码；二维码会话、轮询、取消和凭据保存均复用后端 browser-auth contract。清除登录不会修改外部平台账号。

## 自适应行为

- Compact：账号卡片纵向排列，账号动作在内容下方换行；详情使用单一可滚动信息流。
- Medium/Expanded：列表内容限制最大宽度，状态和动作在空间足够时同行展示；详情始终使用限宽单列，状态之后立即给出连接/检查动作，能力用紧凑行呈现；仅有问题时展示折叠修复指南。
- 列表到详情使用独立语义路由，返回保持账号中心上下文。

## 承担职责

- 已连接平台身份、登录状态、同步认证摘要和修复动作。
- 平台登录会话和手动平台凭据的用户控制面。

## 不承担职责

- 不管理服务器地址、VaultStream API 密钥或网络代理；这些属于设置。
- 不展示收藏同步、发现或分发的完整运行历史。
- 不把“已保存凭据”解释为“真实业务调用已通过”。

## API 关联

- `GET /api/v1/platform-health`
- `/api/v1/browser-auth/*`
- 平台敏感设置沿用现有 settings contract，不进入日志或 URL query。

## 尚未实现 / 计划扩展

- 真实平台登录与失效恢复仍需要具备对应账号时人工验收。
- 后端当前没有返回平台细粒度 OAuth scope，因此详情只展示真实能力状态，不虚构 scope 清单。
