# 精简与重构实施记录

基线：`01e3e223`。分支：`repository-consolidation`。本地实现与验收完成；后续已于 2026-09-27 将 cfbbba78 部署到生产，见下方部署记录。

## 完成范围

- 删除未引用的 B 站旧模型、ArchiveBuilder 类、Flutter 开发控制器、旧 smoke 脚本；TaskQueue 合入唯一 queue 模块。
- 删除首次配置向导、专属登录弹窗及完成状态；连接鉴权保留，模型和账号统一使用设置页与账号中心。三类模型共用编辑/保存组件，保留各自必要字段。
- RSS 发现与收藏共用解析器，保留游标、分类、媒体和来源信息；区分有效空订阅与失败，抓取错误不回显私有 URL。
- 通用解析保留语义 HTML 的零模型路径；其余正文边界、元数据、行修改合成一次有严格校验的提取。复杂 HTML 的定位调用仍独立，不能宣称所有页面只调用一次。
- Gemini 向量使用原生异步 SDK、每请求最多 16 个独立 Content、一次操作复用客户端；保留逐分块失败与重试、缓存、媒体定位、版本检查和原文删除保护。按内容提交，避免跨下一次模型请求持有写锁。
- 16 处分发状态修改共用领取检查与状态转换；发送结果待核对时仍阻止重发。媒体 payload 构造移入 push/media.py，删除单方法包装类。
- Telegram Application 随 API leader 异步启停；删除子进程/PID/系统服务及自报心跳，业务仍走同一 API contract 的进程内 ASGI transport。保留开关、身份持久化、任务回执、失败清理和鉴权。QQ 与 Telegram 账号同步不变。

明确排除 Agent 工具循环：`services/agent/` 和 `core/llm_factory.py` 无修改。主工作区 51 个已有未提交/未跟踪文件逐文件哈希核对未变，未覆盖原有模型工作流修改。

## 验证与范围

- Flutter analyze 无问题；release Web 构建通过。构建提示已有依赖不支持 Wasm 试编译，不影响本次 JS Web 产物。没有宣称安卓真机验收。
- 隔离数据库与真实前端构建：390×844、844×390、1280×900；首次连接直接进入主页、模型表单滚动与保存。非法维度 12 明确提示且不落盘，768 保存成功；重新打开后密钥脱敏，留空再次保存不覆盖原值，数据库核对通过。
- RSS 临时输入：RSS/Atom、CDATA/BBCode、相对图片、日期、24 条完整抓取、旧游标、有分类、空订阅与 HTTP 403。两个入口正文/媒体一致，失败不推进游标，不回显 URL token。
- 通用解析：临时替身验证字段类型、越界、无效删除项和供应商失败；明确语义 HTML 零模型。另经官方 DeepSeek API 实测自建文章、320 段长文、论坛三组输入，各提取一次，指定首中尾内容与图片保留、广告移除。耗时 1.27/1.36/1.23 秒，仅代表这三个样本，不是对比性能结论。
- 向量：真实 Google SDK 配合受控 HTTP transport，21 分块按 16+5 请求并正确配对，预估 2 次；缓存复用、无效向量逐项失败与仅重试失败项、原文在请求期间更新后的拒绝提交通过。未用生产收藏调用 Gemini。
- 分发：真实 ASGI 与数据库验证未知发送结果返回 409；明确立即发送保持尝试次数并清理旧错误、保留显式授权；移入 push 的 payload 构造通过。未发送外部消息。
- Telegram：真实 ASGI、数据库和 Telegram Application，仅替换外部 Telegram transport；启停/重启、进程内 chat upsert、身份持久化与状态读取通过。getMe、setMyCommands、deleteWebhook 三种失败均清理资源，错误响应不泄露 token，非运行者拒绝启动。未宣称 Telegram 真实账号端到端验收。
- Python 语法、直接依赖覆盖、Bandit high/high、SQLite schema gate 通过；OpenAPI 清单覆盖 162 个 endpoint、58 个 action contract。

一次性探针脚本不入库，验收后删除。没有新增常规单元测试套件。

## 部署边界

只读检查发现服务器同时存在容器和宿主机 API；独立 vaultstream-bot.service inactive，未发现 app.bot.main 进程。本次未停止、重启或部署生产服务。

Telegram 新运行方式要求单 API worker；迁移时先确认实际服务入口并停止旧独立 Telegram 进程，再切换版本，避免相同 Bot 的重复轮询。事件 outbox、leader、run ledger、SQLite/Alembic 和业务 API 均保留。

## 后续生产部署（2026-09-27）

用户授权后，API 与 Web 已切换到 `cfbbba78`。生产入口继续使用原有 Docker Compose，单 API worker、调试重载关闭。旧宿主机开发服务 `vaultstream-api.service` 已停止并禁用，原文件和旧库保留。数据库、配置及旧镜像保留供回滚。

正式域名健康、鉴权、收藏读取和 SSE 连接通过；Telegram 真实账号成功启动监听，QQ 状态为在线。上线前后 66 条正式收藏逐 ID 核对完整；启动清理的 38 条记录都是已过期且没有收藏/分发依赖的 RSS 发现候选。Web 主文件哈希与部署产物一致。未发送测试消息或宣称聊天端到端验收。

Android、Linux、Web 构建均成功。追加核对发现手动构建未使用仓库已有正式签名：相邻两次 ARM64 APK 的 Android Debug 证书不同，不能直接覆盖安装。手动流程已改为复用 Release 的四个签名 Secret，缺失时失败，不再发布临时调试签名的 Release APK；既有调试签名安装不能据此宣称无缝迁移。
