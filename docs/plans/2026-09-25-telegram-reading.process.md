# Telegram 与阅读体验进展

## 2026-09-25

账号登录阻塞：应用申请返回 ERROR，测试凭据扫码及官方 Web 扫码失败；官方 Web 号码登录收不到应用内验证码。用户确认现有官方客户端正常收消息。未获取授权会话，尚未实现或验收频道自动同步和 Saved Messages 导入。

已完成 UI 文案和阅读模板首轮收敛：普通错误不附请求 ID、HTTP 状态或原始异常；可选内容缺失省略，阅读页不显示解析内部错误；短帖／主页图片翻页，文章附图按顺序完整展示，去除部分嵌套背景和多余标题。

真实阅读验收使用本地 release Web + 已部署后端，通过只读代理访问现有收藏。代理仅调整首次设置状态、媒体同源地址并关闭 SSE，禁止写请求；不是生产登录或完整同步 E2E。

复跑：`flutter build web --release --no-pub --no-wasm-dry-run`，再运行 `.venv/bin/python backend/manual_tests/reading_preview_20260925.py`。脚本依赖本机已有私有数据库快照 `/tmp/vaultstream-server-backup-20260925/preupgrade.db` 获取 API token，不包含凭据、不提交快照。打开 `http://127.0.0.1:18792`，服务地址填 `http://127.0.0.1:18792/api/v1`、令牌填 `local-readonly-preview`。页面仅执行读取，退出预览即完成重置；生产数据不变。

固定样本与实际结果：

- 收藏 589：桌面及 390×844 下正文换行和滚动正常；原始正文含重复标题及失效图片，这些存量内容尚未修复。
- 收藏 1630：390×844、844×390 下文章标题／正文可读，短横屏正文可滚动；内嵌图片存在缺失，不能称为媒体全部通过。
- 收藏 26438：844×390 下归档图片可见，点击“查看大图”打开 1/1 查看器。
- `flutter analyze --no-pub` 无问题，release Web 构建成功。未新增单元测试。

发现并修复线上普通 IPv6 检查触发 AttributeError，导致收藏列表返回 500 的问题；只修改 IPv4 映射判断。部署后统一搜索接口返回 200、10 条收藏，归档图片返回 200（image/png，3317 字节）。原始 API 快照保留在本机 `/tmp/vaultstream-reading-search.json`，包含私有内容，不提交。

后端镜像：`vaultstream-api:20260925-reading`，包含 IPv6 修复与动态预览 Markdown 清理。前端已部署 `vaultstream-web:5f930d1b`，容器 running、HTTP 200；部署产物 main.dart.js 与本机构建 SHA-256 一致：`ecfd73aadb5ed289dc0a6e10f26872fe4d840314124edbfaacf05281e9a2780d`。
