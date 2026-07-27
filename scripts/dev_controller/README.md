# Flutter 本地开发控制器

## 用途

控制器在本机持有 Flutter Web 调试进程，让 Codex 可以通过受限任务执行热重载、热重启、日志读取、代码生成、静态分析和测试，而不需要操作通用终端界面。

它只监听 `127.0.0.1`，不提供任意命令、任意参数、任意工作目录或环境变量入口。控制令牌只写入被 Git 忽略的 `.runtime/dev-controller.json`。

## 启动

在仓库根目录的内置终端运行：

```powershell
.\scripts\dev_web.ps1
```

默认端口：

- Flutter Web：`8123`
- 控制器：`8791`
- 后端 API：`http://127.0.0.1:8008/api/v1`

控制器固定使用 `--web-hostname 127.0.0.1`，并通过 `--dart-define=API_BASE_URL=http://127.0.0.1:8008/api/v1` 连接本地后端，避免启动方式不同造成 API 端口漂移。

如果已有旧的前端进程占用 `8123`，先正常停止旧进程，再启动控制器。控制器不会接管或结束不是由它创建的进程。

也可以只启动控制面，稍后再启动 Flutter：

```powershell
.\scripts\dev_web.ps1 --no-start
.\scripts\devctl.ps1 start
```

## 白名单任务

```powershell
.\scripts\devctl.ps1 status
.\scripts\devctl.ps1 start
.\scripts\devctl.ps1 reload
.\scripts\devctl.ps1 restart
.\scripts\devctl.ps1 stop
.\scripts\devctl.ps1 shutdown
.\scripts\devctl.ps1 logs --limit 100
.\scripts\devctl.ps1 generate
.\scripts\devctl.ps1 analyze
.\scripts\devctl.ps1 format-check
.\scripts\devctl.ps1 test
.\scripts\devctl.ps1 test test/widget/collection_page_test.dart
```

`reload` 发送 Flutter 热重载，`restart` 发送热重启。控制器不会在热重载失败时偷偷执行热重启。

`test` 的目标路径必须真实存在于 `frontend/test/` 且以 `_test.dart` 结尾。`reporter` 只允许 `compact`、`expanded` 和 `json`。其他工具任务使用固定参数数组并以 `shell=False` 启动。

## 状态和结果

`status` 返回 Flutter PID、应用 ID、是否支持重载、Web URL、DevTools URL、构建代数及最近一次重载结果。构建代数只在 Flutter 明确返回重载成功后增加。

一次性工具任务串行执行，避免 `build_runner`、分析和测试争用。客户端默认等待完成并沿用工具退出码；使用 `--no-wait` 可以只取得任务 ID。

日志最多保留 500 行，控制器会对常见 Token、Cookie、Authorization 和签名查询参数进行脱敏。日志脱敏是最后一道保护，应用本身仍不应打印凭据。

## 停止控制器

`devctl stop` 只停止控制器持有的 Flutter 子进程。使用 `devctl shutdown` 或在启动终端按 `Ctrl+C` 才会结束控制器本身；控制器会先结束自己的任务和 Flutter 子进程，再删除运行时文件。
