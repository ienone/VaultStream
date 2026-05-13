# 安全审计

## P0/P1 风险

### 1. 前端默认日志会记录 API token

`frontend/lib/core/network/api_client.dart` 在 `EnvConfig.debugLog` 为 true 时启用 Dio `LogInterceptor(requestHeader: true, requestBody: true, responseBody: true)`。`frontend/lib/core/config/env_config.dart` 中 `DEBUG_LOG` 默认值为 true；API token 又通过 header `X-API-Token` 发送。

影响：

- token 可能出现在开发机、Web console、Android logcat、CI 构建日志或用户反馈截图中。
- 如果 release 构建未显式传 `--dart-define=DEBUG_LOG=false`，风险会进入发布包。

建议：

- 默认 `DEBUG_LOG=false`。
- 即使 debug 开启，也 redacts `X-API-Token`、`Authorization`、cookie、bot token。
- CI/release workflow 明确传入 `--dart-define=DEBUG_LOG=false`。

### 2. `lxml 5.4.0` 存在已知漏洞

`pip-audit` 发现：

- 包：`lxml`
- 当前版本：`5.4.0`
- 漏洞：`CVE-2026-41066` / `GHSA-vfmq-68hx-4jfw`
- 修复版本：`6.1.0`
- 风险：默认 XML parser 的 entity 解析行为可能在处理不可信 XML 时导致本地文件读取。

建议：

- 升级到 `lxml>=6.1.0`。
- 对任何不可信 XML/HTML 解析显式禁用外部实体或使用安全 parser。
- 升级后跑 adapter/parser 相关测试。

### 3. 图片代理 debug 模式绕过 SSRF 防护

`backend/app/routers/media.py:24-49` 的 `_is_safe_url()` 会解析 hostname 并阻止 private/reserved/link-local 地址，但 `settings.debug` 为 true 时跳过 IP 检查。`/proxy/image` 无需 API Token，接受任意 URL 并下载、转码、缓存。

影响：

- 开发/测试部署如果暴露到局域网或公网，可能访问 `127.0.0.1`、内网服务或云元数据地址。
- `client.get(... follow_redirects=True)` 后没有看到重定向目标的二次 IP 校验。
- 下载使用 `resp.content` 一次性读入内存，且未看到 Content-Length 上限。

建议：

- SSRF 防护不应因 debug 全量关闭；可只对白名单域名或显式本机开发开关放行。
- 对每次 redirect 后的最终 URL/IP 再校验。
- 给远程图片代理增加最大响应体限制、content-type allowlist、缓存配额。
- 考虑给 `/proxy/image` 加 token、签名 URL 或 referer/origin 限制。

### 4. 外部 URL 打开未统一校验

多个 Flutter 组件直接执行：

```dart
launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)
```

典型位置：

- `frontend/lib/features/collection/content_detail_page.dart:264`
- `frontend/lib/features/collection/widgets/detail/content_detail_sheet.dart:148`
- `frontend/lib/features/collection/widgets/detail/components/author_header.dart:149`
- `frontend/lib/features/collection/widgets/detail/layout/user_profile_layout.dart:198`
- `frontend/lib/features/collection/widgets/detail/components/zhihu_top_answers.dart:77`

建议全部改为现有 `safe_url_launcher.dart`，只允许 `http`/`https`，并统一失败提示。

## 其他安全问题

### API token 生命周期

- `backend/app/core/dependencies.py` 在 expected token 为空时放行。
- `backend/app/main.py` 启动时会生成 token，但首次生成会输出到日志。
- `frontend/lib/core/providers/local_settings_provider.dart` 将 `api_token` 存入 `SharedPreferences`。

建议：

- 生产环境强制要求显式 `API_TOKEN` 或受保护的 secret store。
- 启动日志只显示 token 指纹，不打印完整 token。
- 移动端优先使用平台安全存储，而不是 SharedPreferences。

### WebSocket token 传递

`backend/app/routers/agent.py` 支持 query token、`x-api-token`、Bearer。query token 可能进入代理日志和浏览器历史。

建议：WebSocket 只接受 header/subprotocol token，或在文档中禁止 query token 用于生产。

### Docker 安全基线

`backend/Dockerfile` 使用 root 运行，安装 Playwright WebKit 依赖、ffmpeg、curl，攻击面较大。建议：

- 创建非 root 用户运行应用。
- 分离 crawler/browser 能力和 API 主服务，或在容器级别做 seccomp/cap drop。
- 加镜像漏洞扫描和 SBOM。

### CI 安全门禁

当前 workflow 未见 `pip-audit`、Bandit、secret scanning、Flutter release debug flag 检查。建议作为 release 前置门禁。

