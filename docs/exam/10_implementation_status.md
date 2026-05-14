# 审计问题实现状态总览

更新日期：2026-05-14

本文对 `docs/exam` 下审计发现逐项复核当前代码状态，结论以代码、测试和最近 commit 为准。状态定义：

- 已修：代码已落地，且有测试或静态证据支撑。
- 部分修复：主风险已降低，但仍有边界或验证缺口。
- 未修：未看到实质代码变更。
- 假修复/弱验证：表面有改动或文档声明，但仍不满足原风险目标，或验证证据不足。

## 总览

| 主题 | 状态 | 证据 | 仍需处理 |
| --- | --- | --- | --- |
| 后端 pytest 收集失败 | 已修 | `test_content_summary.py` 已使用 `generate_summary_for_content`；非 integration 测试通过 | 全量 real/integration 仍依赖外部服务 |
| 前端敏感日志 | 已修 | `DEBUG_LOG=false` 默认值、Dio redaction、workflow 显式 false | 继续避免业务代码手写 `print` token/cookie |
| `lxml 5.4.0` 漏洞 | 已修 | `backend/requirements.txt` pin `lxml>=6.1.0`；本地 `pip-audit` 通过：No known vulnerabilities found | 继续在 CI/release 中执行 pip-audit |
| 图片代理 SSRF/大文件 | 已修 | URL 安全校验、redirect 重验、Content-Length/累计大小限制、content-type allowlist、像素尺寸限制、生产 Origin/Referer 限制、缓存配额均已落地 | 未加入签名 URL；若未来代理面向第三方站点/CDN 暴露再补短时效签名 |
| 外部 URL 打开 | 已修 | `frontend/lib` 直接 `launchUrl(` 仅剩 `safe_url_launcher.dart` | 继续为新增页面加测试 |
| FTS 缺表/静默失败 | 已修 | `ensure_content_fts()` 创建表、trigger、backfill；health 暴露 FTS；搜索降级 warning once | 需补迁移版本化/DB 门禁脚本 |
| Flutter codegen 口径 | 部分修复 | CI 已有 build_runner + analyze/test；本地提权验证通过 | README/开发脚本仍可进一步固化一键验证 |
| Adapter 生命周期 | 已修 | `close_adapter/open_adapter` 已接入解析和分享主路径 | 继续审计脚本/边缘 adapter |
| Google Fonts 运行时拉取 | 已修 | `configureRuntimeAssets()` 禁用 runtime fetching，widget test 覆盖 | 后续可打包字体资产进一步优化首屏 |
| Discovery post-ingest | 已修 | parse/discovery/share 接入 `PostIngestService`，覆盖 summary/embedding/distribution | favorites 全链路仍需抽样确认 |
| 向量检索 O(N) | 部分修复 | 已有候选限制、耗时日志、`VECTOR_SEARCH_EVALUATION.md` | 尚未引入 sqlite-vec；需按阈值触发试点 |
| 后台任务诊断 | 已修 | `background_task_state` + `/health` task_states | 还缺失败队列详情页/指标导出 |
| Docker root 用户 | 已修 | Dockerfile 已使用非 root 用户和 healthcheck | 仍需镜像扫描/SBOM |
| CI 安全门禁 | 已修 | quality/release 有 pytest、pip-audit、Bandit、Flutter、Trivy、DEBUG_LOG、Gitleaks；本地 pip-audit/Bandit 通过 | 后续可补 SBOM 产物留档 |
| Agent/Bot typed DTO | 部分修复 | Agent 前端有 sealed result；Bot 有 typed model；Discovery list 已有 response schema | review render config 等仍大量 `Map<String,dynamic>` |
| API 文档漂移 | 已修 | `scripts/check_openapi_docs.py` 比对 FastAPI OpenAPI 与 `docs/API.md`；quality/release 均接入；本地 92 endpoints 通过 | 继续要求新增 endpoint 同步文档 |
| 资源泄漏 warning | 已修 | 修复 async mock 未 await；测试 engine 使用 `NullPool` 并 dispose app/test engine；全量非 integration 在 `-W error::ResourceWarning` 下通过 | 继续要求新增 fixture 显式关闭 async engine/session |
| Vulture 候选 | 未修 | 未做批量死代码删除 | 需人工筛选后小批次删除 |
| 图片缓存库边界 | 未修 | 未看到统一策略改动 | 需收敛 cached_network_image / extended_image 用途 |
| API token 本地存储 | 已修 | 启动时迁移 legacy `SharedPreferences` token 到 `flutter_secure_storage`；设置/清除 token 均写安全存储并清理旧 key | Web 平台安全属性依赖浏览器/插件实现，仍不应把 token 写入日志 |
| Distribution 决策入口 | 未修 | engine/scheduler/parsing 仍并存 | 需收敛单一业务入口并补回归测试 |
| Browser manager shutdown | 已修 | `join(timeout=5s)` 并记录未退出错误 | 可补单元测试模拟线程未退出 |
| Discovery list raw dict | 已修 | `/discovery/items` 改为 `DiscoveryItemListResponse` | 可补 OpenAPI schema 快照 |
| Agent tool error | 已修 | HTTP/WS 返回结构化 `error_code`；Agent 页面按错误码展示可恢复提示并保留 RID | 仍可继续补 WS 流式交互的细粒度 UI 状态 |

## 假修复/弱验证清单

1. 向量检索：已有候选收敛和评估文档，但这不是专用向量索引。数据量超过阈值后仍可能退化。
2. 后台任务诊断：`/health` 有 task state，但还不是完整“失败面板”；没有逐项失败记录、重试明细和可视化入口。
3. Agent 类型化：前端展示模型已有，但后端 tool result schema 仍主要是 `dict`，还没做到端到端 schema 生成或契约测试。
4. 图片代理：像素限制、缓存配额和生产 Origin/Referer 限制已落地；但未做签名 URL。如果未来把代理暴露给第三方站点或 CDN，应再补签名/短时效策略。

## 下一批建议

1. P2：收敛 Distribution 决策入口，保留一个 service 作为业务入口。
2. P2：人工筛选 Vulture 候选，按小批次删除死代码。
3. P2：收敛前端图片缓存库边界，明确 `cached_network_image` 与 `extended_image` 的职责。
4. P2：按向量检索评估阈值启动 sqlite-vec/sqlite-vss 试点。
