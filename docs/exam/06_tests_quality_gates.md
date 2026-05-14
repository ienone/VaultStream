# 测试与 CI 审计

## 本次验证结果

### 后端 pytest

命令：

```powershell
.venv\Scripts\python.exe -m pytest backend/tests -q
```

2026-05-14 复核结果：非 integration 后端测试已通过。

```powershell
.venv\Scripts\python.exe -m pytest backend\tests -q -m "not integration"
```

结果：`646 passed, 4 skipped, 16 deselected`。该命令在 `-W error::ResourceWarning` 下通过，测试侧 SQLite ResourceWarning 已收敛。

### pip-audit

命令：

```powershell
.venv\Scripts\python.exe -m pip_audit -r backend\requirements.txt -f json
```

2026-05-14 复核结果：通过，`No known vulnerabilities found`。

### Bandit

命令：

```powershell
.venv\Scripts\python.exe -m bandit -r backend\app -f json -q
```

2026-05-14 复核结果：按 high severity / high confidence 门禁通过，`No issues identified`。低严重度项仍可按常规清理节奏处理。

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

- `flutter analyze` 通过：`No issues found! (ran in 10.8s)`。
- `flutter test` 通过：`All tests passed!`。

说明：此前从 repo root 或在 sandbox 内并行执行 `flutter analyze/test` 出现超时，该结果不能作为 Flutter 项目失败证据。正确口径应以 `frontend` 目录下、顺序执行的结果为准。

补充观察：Dio 日志和 API token 本地存储已整改；`flutter test` 仍有一个既有 widget `tap()` offset warning，未导致测试失败。

## CI 现状

### `.github/workflows/build.yml`

观察到 workflow_dispatch 构建 Android/Web/Linux，并运行 build_runner。安全/质量门禁主要集中在 `.github/workflows/quality.yml` 与 `.github/workflows/release.yml`。

- backend pytest
- Flutter analyze
- Flutter test
- pip-audit
- bandit
- Docker image scan

### `.github/workflows/release.yml`

tag push 发布 APK 和 Docker image。当前 release quality-gates 已包含 backend pytest、pip-audit、Bandit、OpenAPI 文档比对、Gitleaks 和 DEBUG_LOG 检查。

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
.venv\Scripts\python.exe scripts\check_openapi_docs.py
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
