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
| `lxml 5.4.0` 漏洞 | 已修 | `backend/requirements.txt` pin `lxml>=6.1.0`；本地 `.venv` 为 6.1.0；`pip check` 通过 | `pip-audit` 最新重跑受 PyPI SSL EOF 影响，需在网络稳定时重跑 |
| 图片代理 SSRF/大文件 | 部分修复 | 已有 URL 安全校验、redirect 重验、Content-Length/累计大小限制、content-type allowlist | 缺像素尺寸限制、origin/signature、缓存配额 |
| 外部 URL 打开 | 已修 | `frontend/lib` 直接 `launchUrl(` 仅剩 `safe_url_launcher.dart` | 继续为新增页面加测试 |
| FTS 缺表/静默失败 | 已修 | `ensure_content_fts()` 创建表、trigger、backfill；health 暴露 FTS；搜索降级 warning once | 需补迁移版本化/DB 门禁脚本 |
| Flutter codegen 口径 | 部分修复 | CI 已有 build_runner + analyze/test；本地提权验证通过 | README/开发脚本仍可进一步固化一键验证 |
| Adapter 生命周期 | 已修 | `close_adapter/open_adapter` 已接入解析和分享主路径 | 继续审计脚本/边缘 adapter |
| Google Fonts 运行时拉取 | 已修 | `configureRuntimeAssets()` 禁用 runtime fetching，widget test 覆盖 | 后续可打包字体资产进一步优化首屏 |
| Discovery post-ingest | 已修 | parse/discovery/share 接入 `PostIngestService`，覆盖 summary/embedding/distribution | favorites 全链路仍需抽样确认 |
| 向量检索 O(N) | 部分修复 | 已有候选限制、耗时日志、`VECTOR_SEARCH_EVALUATION.md` | 尚未引入 sqlite-vec；需按阈值触发试点 |
| 后台任务诊断 | 已修 | `background_task_state` + `/health` task_states | 还缺失败队列详情页/指标导出 |
| Docker root 用户 | 已修 | Dockerfile 已使用非 root 用户和 healthcheck | 仍需镜像扫描/SBOM |
| CI 安全门禁 | 部分修复 | quality/release 有 pytest、Bandit、Flutter、Trivy、DEBUG_LOG 检查 | 缺稳定 pip-audit、secret scanning |
| Agent/Bot typed DTO | 部分修复 | Agent 前端有 sealed result；Bot 有 typed model；Discovery list 已有 response schema | review render config 等仍大量 `Map<String,dynamic>` |
| API 文档漂移 | 部分修复 | `docs/API.md` 已覆盖更多 endpoint、健康诊断、鉴权说明 | 应用 OpenAPI 自动比对防回退 |
| 资源泄漏 warning | 未修 | 非 integration 测试仍有 unclosed sqlite/async mock warning | 需单独修 fixture/session 生命周期 |
| Vulture 候选 | 未修 | 未做批量死代码删除 | 需人工筛选后小批次删除 |
| 图片缓存库边界 | 未修 | 未看到统一策略改动 | 需收敛 cached_network_image / extended_image 用途 |
| API token 本地存储 | 未修 | 前端仍用 SharedPreferences 存 `api_token` | 迁移到平台安全存储 |
| Distribution 决策入口 | 未修 | engine/scheduler/parsing 仍并存 | 需收敛单一业务入口并补回归测试 |
| Browser manager shutdown | 已修 | `join(timeout=5s)` 并记录未退出错误 | 可补单元测试模拟线程未退出 |
| Discovery list raw dict | 已修 | `/discovery/items` 改为 `DiscoveryItemListResponse` | 可补 OpenAPI schema 快照 |
| Agent tool error | 部分修复 | HTTP/WS 返回结构化 `error_code` | 前端还未基于错误码做恢复式交互 |

## 假修复/弱验证清单

1. `pip-audit` 门禁：requirements 已修，且之前跑通过；但最新重跑受 PyPI SSL EOF 影响失败。不能把当前网络失败当作安全门禁绿灯，需要在 CI 或稳定网络中重跑。
2. 向量检索：已有候选收敛和评估文档，但这不是专用向量索引。数据量超过阈值后仍可能退化。
3. 后台任务诊断：`/health` 有 task state，但还不是完整“失败面板”；没有逐项失败记录、重试明细和可视化入口。
4. Agent 类型化：前端展示模型已有，但后端 tool result schema 仍主要是 `dict`，还没做到端到端 schema 生成或契约测试。
5. 图片代理：SSRF 和大小限制主风险已降，但缓存配额、像素炸弹和访问来源限制还没闭环。

## 下一批建议

1. P1：前端 token 迁移到 secure storage，并提供兼容迁移。
2. P1：图片代理增加像素尺寸限制、缓存配额和 origin/signature 限制。
3. P1：修复测试中的 SQLite ResourceWarning，避免隐藏真实连接泄漏。
4. P2：为 OpenAPI endpoint 清单增加自动比对脚本。
5. P2：收敛 Distribution 决策入口，保留一个 service 作为业务入口。
