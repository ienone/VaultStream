# 测试与 CI 审计

## 本次验证结果

### 后端 pytest

命令：

```powershell
.venv\Scripts\python.exe -m pytest backend/tests -q
```

结果：失败，收集阶段报错：

```text
ImportError: cannot import name 'generate_summary_llm' from 'app.services.content_summary_service'
```

结论：当前后端测试门禁不可用，需要先修复测试/实现契约。

### pip-audit

命令：

```powershell
.venv\Scripts\python.exe -m pip_audit -r backend\requirements.txt -f json
```

结果：发现 `lxml 5.4.0` 漏洞，修复版本 `6.1.0`。

### Bandit

命令：

```powershell
.venv\Scripts\python.exe -m bandit -r backend\app -f json -q
```

结果：1 个 HIGH，49 个 LOW。HIGH 是 `embedding_service.py:506` 的 MD5。该处用于本地 embedding hashing，不一定是密码学风险，但应改为 `usedforsecurity=False` 或换成非安全用途更明确的 hash，并加测试/注释。

### Vulture

命令：

```powershell
.venv\Scripts\python.exe -m vulture backend\app backend\tests --min-confidence 80
```

结果：返回多处未使用代码候选。建议人工筛选，不建议一次性自动删除。

### Flutter

命令：

```powershell
cd frontend
flutter analyze
flutter test
```

结果：

- `flutter analyze` 通过：`No issues found! (ran in 15.2s)`。
- `flutter test` 通过：`All tests passed!`，总耗时约 24.8s。

说明：此前从 repo root 或在 sandbox 内并行执行 `flutter analyze/test` 出现超时，该结果不能作为 Flutter 项目失败证据。正确口径应以 `frontend` 目录下、顺序执行的结果为准。

补充观察：`flutter test` 输出中多次打印 Dio request header，包括 `X-API-Token:`。即使本次 token 为空，也说明前端日志脱敏风险是真实存在的。

## CI 现状

### `.github/workflows/build.yml`

观察到 workflow_dispatch 构建 Android/Web/Linux，并运行 build_runner，但未看到：

- backend pytest
- Flutter analyze
- Flutter test
- pip-audit
- bandit
- Docker image scan

### `.github/workflows/release.yml`

tag push 发布 APK 和 Docker image，但未看到 release 前测试/审计门禁。Android/Web release build 也未看到明确 `--dart-define=DEBUG_LOG=false`。

## 可观测性与故障恢复

### P1：降级状态不可见

FTS 缺表会在 `text_search.py` 中被吞掉并返回空列表；这类关键能力降级应进入 health check 或结构化日志。建议 `/api/v1/health` 增加 database、`contents_fts`、background worker、embedding provider 状态。

### P2：后台任务缺少统一失败面板

解析 worker、distribution worker、Discovery sync、favorites sync、maintenance task 都在 lifespan 或后台任务中启动，但没有看到统一任务状态、最近错误、重试次数、失败队列的诊断入口。建议暴露 worker running/stopped、last_success_at、last_error_at、pending/running/failed/retry counts。

### P2：日志结构不统一

部分路径使用普通字符串日志，部分异常会直接拼接 URL/token 风险字段。建议统一 structured logging 字段，并对 URL query、token、cookie、bot credential 做 redaction。

## 建议门禁

### PR 必跑

```powershell
.venv\Scripts\python.exe -m pytest backend/tests -q
cd frontend
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

### 每日或 release 必跑

```powershell
.venv\Scripts\python.exe -m pip_audit -r backend\requirements.txt
.venv\Scripts\python.exe -m bandit -r backend\app
.venv\Scripts\python.exe -m vulture backend\app backend\tests --min-confidence 80
```

### 数据库门禁

新增一个 lightweight DB check：

- `PRAGMA integrity_check`
- `PRAGMA foreign_key_check`
- 检查关键表：`contents`、`content_sources`、`content_queue_items`、`content_embeddings`
- 检查可选能力表：`contents_fts`
- 检查 migration version 或 schema version

## 测试缺口

1. Summary/RAG：summary service 配置、LLM mock、rich_payload chunks 写入。
2. FTS：FTS 表创建、触发器同步、缺表降级告警。
3. Discovery：入库后是否触发 embedding/patrol/distribution。
4. Media proxy：SSRF、redirect、Content-Length、非图片响应、大文件。
5. Agent：tool args schema、错误码、websocket token、stream event contract。
6. Frontend：safe URL launcher、SSE reconnect/refresh、bot config typed DTO、agent result rendering。
