# HTTP QR 登录迁移方案

> 目标：完全移除 `BrowserAuthService` 中的 Playwright 依赖，改为三平台各自的纯 HTTP QR 流程。
> API surface（`/auth/session/*`、`/auth/{platform}/check`）保持不变，前端零修改。

---

## 现状与目标

### 现状（`browser_auth_service.py`）

```
PlaywrightBrowserManager（独立后台线程 + ProactorEventLoop）
    └── _auth_flow_pw_job()
           1. browser.new_context() → 打开真实浏览器
           2. page.goto(login_url)  → 导航到登录页，等待 DOM 渲染
           3. 截图 canvas/img 元素 → base64 → 推给前端
           4. 每 2s 轮询 DOM 选择器 / cookie 判断成功
           5. context.cookies() 全量导出 → set_setting_value()
```

**问题清单：**

| 问题 | 影响 |
|------|------|
| 冷启动需要初始化 Playwright + WebKit 进程 | 首次登录等待 3–5 秒 |
| XHS/Zhihu QR 来自截图，质量依赖 DPI | 服务器环境扫码失败率高 |
| 成功检测依赖 DOM 选择器（`.AppHeader-profile` 等） | UI 更新即失效 |
| `check_platform_status` 也走浏览器 | 每次健康检查启动完整页面 |
| `playwright` 是重型依赖，Docker 镜像体积大 | 部署复杂 |

### 目标

完全替换为纯 `httpx.AsyncClient` 流程，去掉 `PlaywrightBrowserManager` 和所有 Playwright 代码，**不保留回退逻辑**。

---

## 各平台 HTTP QR 流程（已验证）

> 参考实现见 `tests/qr_login_benchmark/verify_login.py`

### 小红书（XHS）

**依赖：** `xiaohongshu-cli` 库（`xhs_cli.signing`, `xhs_cli.constants`）

**HTTP 客户端：** `httpx.AsyncClient`

```
1. POST /api/sns/web/v1/login/activate
   → 生成随机 a1 / webId，激活匿名 session，获取 web_session cookie（非致命）

2. POST /api/sns/web/v1/login/qrcode/create  { qr_type: 1 }
   → 获取 { qr_id, code, url }
   → url 字段即 QR 内容，直接 qrcode.make(url) → base64 给前端

3. 轮询 POST /api/qrcode/userinfo  { qrId, code }  每 2s
   codeStatus: 0=等待, 1=已扫码, 2=已确认

4. codeStatus==2 时：GET /api/sns/web/v1/login/qrcode/status?qr_id=&code=
   → 获取 web_session, web_session_sec（最终 session switch）

关键 Cookie: a1, webId, web_session
```

**签名注意：** 所有请求须通过 `sign_main_api()` 生成 `X-s`/`X-t`/`X-b3-traceid` 等签名头；cookie 字典须同步传入 sign 函数。

---

### 微博（Weibo）

**HTTP 客户端：** `httpx.AsyncClient`

```
1. GET https://passport.weibo.com/sso/v2/qrcode/image?size=180
   → 获取 { qrid, image }
   → 从 image URL 的 ?data= 参数提取扫码内容，qrcode.make(scan_url) → base64 给前端

2. 轮询 GET /sso/v2/qrcode/check?qrid=  每 2s
   retcode: 50114002=已扫码, 20000000=已确认

3. 确认后：从响应体取 data.alt（SSO 跳转 URL）
   → 跟随 SSO 多级跳转链（follow_redirects=True）
   → 通过 client.cookies.jar 迭代收集所有 cookie
     ⚠️ 必须用 .jar 迭代而非 .items()，否则同名 cookie（如 SCF）触发 httpx.CookieConflict

关键 Cookie: SUB, SSOLoginState
```

---

### 知乎（Zhihu）

**HTTP 客户端：** `httpx.AsyncClient`（已验证可完全替代 requests）

**关键约束（两阶段头部）：**

| 阶段 | 头部要求 |
|------|---------|
| 预热（`/signin`, `/udid`, `/captcha`） | 只带基础浏览器头，**禁止** `sec-fetch-*` / `x-zse-93` |
| 轮询（`/scan_info`） | 追加 `sec-fetch-dest: empty`，`sec-fetch-mode: cors`，`sec-fetch-site: same-origin`，`x-zse-93: 101_3_3.0` |
| 每次请求 | 从 jar 读取 `_xsrf`，设 `x-xsrftoken` |

**Cookie domain 补偿：** httpx 的 `Set-Cookie` domain 匹配比 requests 严格。每次轮询响应后必须手动吸收：
```python
for c in resp.cookies.jar:
    client.cookies.set(c.name, c.value, domain=".zhihu.com")
```

```
1. GET /signin        → _xsrf, d_c0（只带基础头）
2. POST /udid         → 补全 d_c0, q_c1
3. GET /captcha/v2    → 跳过（让服务端决定）
4. POST /api/v3/account/api/login/qrcode
   → { token, link }，直接用 link 生成 QR → base64 给前端

5. 轮询 GET /api/v3/account/api/login/qrcode/{token}/scan_info  每 0.15s
   status: 0=等待, 1=已扫码
   成功判断（服务端不一定返回 status 字段）：
     - status 字段不在 (0, 1) 中，且 access_token/user_id 非空   → 成功
     - jar 中出现 z_c0                                           → 成功
     - 其余 login_status 字符串兜底

6. 若 z_c0 未在轮询中到达：GET /api/v4/me（补偿触发完整 cookie 下发）

关键 Cookie: z_c0
```

**⚠️ 人机验证（code 40352）：**

知乎可能在轮询中返回：
```json
{"error": {"code": 40352, "need_login": true,
           "redirect": "https://www.zhihu.com/account/unhuman?type=S6E3V1&..."}}
```
这是 IP/行为风控触发的。当前在 `verify_login.py` 中的处理方式：自动打开浏览器 + 延长超时 60s。

**前端适配（待实现）：** 当后端检测到 40352 时，应通过 SSE/轮询将 `redirect` URL 推给前端，前端提示用户点击链接在新标签页完成验证后继续。session 状态模型需追加一个 `"needs_captcha"` 状态，携带 `captcha_url` 字段。

---

## 需要改动的文件

### 1. `backend/app/services/browser_auth_service.py` — 核心替换

**删除：**
- 整个 `_auth_flow_pw_job()` 方法（Playwright 流）
- 整个 `_check_status_pw_job()` 方法（Playwright 校验）
- `_drive_auth_flow_wrapper()` 中对 `browser_manager.submit_coro()` 的调用
- `_has_any_selector()` 辅助方法

**新增：**
- `_xhs_qr_flow(session)` — 对应上节 XHS 流程，`httpx.AsyncClient`
- `_weibo_qr_flow(session)` — 对应上节 Weibo 流程，`httpx.AsyncClient`
- `_zhihu_qr_flow(session)` — 对应上节 Zhihu 流程，`httpx.AsyncClient`
- 每个方法内，QR base64 赋值方式改为 `qrcode.make(url/link/scan_url).tobytes()` 再 base64
- `_check_xhs_cookie(cookie_str)` / `_check_weibo_cookie()` / `_check_zhihu_cookie()` — 轻量 HTTP 校验（见下节）
- `AuthSession` 模型追加可选字段 `captcha_url: Optional[str]`（知乎人机验证用）
- `start_auth_session()` 改为直接 `asyncio.create_task(getattr(self, f"_{platform}_qr_flow")(session))`

**保留：**
- `AuthSession` / `AuthSessionStatus` 数据模型（仅追加字段）
- `start_auth_session()` / `get_session_status()` / `get_session_qrcode()` / `cancel_session()` 公开接口
- `logout_platform()` 方法

### 2. `backend/app/services/browser_auth_service.py` — `check_platform_status()` 替换

**删除：** 对 `browser_manager.submit_coro(self._check_status_pw_job(...))` 的调用

**替换为轻量 HTTP 探针：**

| 平台 | 探针请求 | 成功条件 |
|------|---------|---------|
| XHS | `GET https://edith.xiaohongshu.com/api/sns/web/v1/user/me`（带 cookie 头） | HTTP 200，`data.success == true` |
| Weibo | `GET https://api.weibo.com/2/account/verify_credentials.json?access_token=...` 或 `GET https://passport.weibo.com/visitor/visitor?a=init`（带 SUB cookie） | HTTP 200 非重定向到登录页 |
| Zhihu | `GET https://www.zhihu.com/api/v4/me`（带 z_c0 cookie） | HTTP 200，`id` 字段非空 |

### 3. `backend/app/adapters/browser/__init__.py` 和 `manager.py`

**删除：** 整个 `PlaywrightBrowserManager`，`browser_manager` 单例，lifespan 中的 `await browser_manager.startup()` / `shutdown()` 调用。

> 如果项目其他地方（内容抓取等）还依赖 Playwright 浏览器抓取，则仅从 `browser_auth_service` 中解耦，保留管理器但不在 auth 路径使用。

### 4. `backend/app/main.py` — lifespan 清理

删除 `browser_manager.startup()` / `browser_manager.shutdown()` 相关代码（若 manager 完全移除的话）。

### 5. `backend/app/routers/browser_auth.py` — **零修改**

API 路由完全保持不变。唯一可能需要追加：

```python
class AuthSessionStatus(BaseModel):
    ...
    captcha_url: Optional[str] = None   # 知乎人机验证时填充
```

前端轮询 `/session/{id}/status` 时，若 `status == "needs_captcha"`，提示用户打开 `captcha_url`。

### 6. `backend/requirements.txt`

**删除：**
```
playwright
```

**保留（已有）：**
```
httpx
qrcode[pil]
```

---

## Cookie 校验与维持策略

### 校验时机

| 时机 | 动作 |
|------|------|
| 前端点击「检查状态」 | 调用 `check_platform_status()` → 轻量 HTTP 探针 |
| 适配器发起内容请求返回 401/403 | 上层 `ContentService` 捕获 `AuthRequiredAdapterError`，标记 cookie 无效，触发前端通知 |
| 定时任务（可选，每 24h） | 主动探针，失效则发通知 |

### Cookie 有效期参考

| 平台 | 关键字段 | 实测有效期 |
|------|---------|---------|
| XHS | `web_session` | ~7 天（xiaohongshu-cli 文档） |
| Weibo | `SUB` | 数周至数月（无固定规律） |
| Zhihu | `z_c0` | 数周（Bearer token 形式，服务端可随时撤销） |

### 失效后处理

无自动刷新机制（无法在后台自动重新扫码）。失效时：
1. `check_platform_status()` 返回 `false`
2. 前端展示「需要重新登录」，引导用户发起新 QR 会话
3. 新会话成功后 `set_setting_value(f"{platform}_cookie", ...)` 覆盖旧值

---

## 实施顺序建议 (✅ 已完成)

| 步序 | 内容 | 状态 |
|------|------|------|
| 1 | Weibo：替换 `_auth_flow_pw_job` 中 weibo 分支为 `_weibo_qr_flow` | ✅ |
| 2 | Weibo：替换 `_check_status_pw_job` weibo 分支为 HTTP 探针 | ✅ |
| 3 | XHS：替换 XHS 分支，集成 `xhs_cli.XhsClient` 的 `create_qr_login`/`complete_qr_login` | ✅ |
| 4 | Zhihu：替换 Zhihu 分支，含 cookie absorb 和人机验证检测 | ✅ |
| 5 | 解耦 `PlaywrightBrowserManager` 与 auth 路径 (保留供 Tier 3 使用) | ✅ |
| 6 | 前端追加 `needs_captcha` 状态处理 (已实现) | ✅ |

每步完成后均可独立部署验证，不影响其他平台。
