# 2026-05 全项目审计摘要

> 来源：旧 `full_project_audit_2026-05-13/` 目录。  
> 当前状态：只保留未完全解决或曾被过度声明完成的事项。

## 原审计结论浓缩

2026-05 的全项目审计确认 VaultStream 已经具备可运行产品形态：FastAPI 后端、SQLite、Flutter 客户端、内容采集、解析、发现、分发、Agent 和 RAG 均有实现。主要问题是功能推进快于工程收敛，质量、安全、契约、性能和文档状态容易漂移。

## 已确认完成并从归档中移除的事项

- 后端非 integration 测试收集失败。
- 前端 `DEBUG_LOG` 默认开启。
- `lxml 5.4.0` 已知漏洞。
- FTS 缺表和搜索静默失败的基础修复。
- Flutter codegen/analyze/test 验证口径。
- 外部 URL 打开集中到 safe launcher。
- Google Fonts runtime fetching 默认禁用。
- Docker 非 root 用户和 healthcheck。
- Discovery list raw dict 基础类型化。
- 3 月服务器端历史 bugfix 记录。

## 仍需处理的遗留风险

| 主题 | 当前状态 | 说明 |
| --- | --- | --- |
| 真实平台 integration 测试 | 未稳定 | 非 integration 通过不能证明知乎、小红书、真实 LLM 等外部链路稳定。 |
| 图片代理 SSRF | 部分缓解 | 已有预检、redirect、大小和类型限制，但连接目标未绑定，仍有 DNS rebinding/解析差异风险。 |
| 归档媒体与通用解析 SSRF | 未修 | RSS/发现源/通用解析/Playwright navigation 仍缺统一 SSRF-safe fetcher。 |
| Browser-auth 鉴权 | 未修 | `/api/v1/browser-auth` 仍未强制 API token。 |
| Telegram Bot 默认权限 | 未修 | 空白名单仍等价 allow-all。 |
| API token 构建注入 | 未修 | manual build workflow 仍可能把共享后端 token 编译进客户端产物。 |
| 向量检索性能 | 短期缓解 | 仍是 JSON 向量表和应用层计算，只是增加扫描上限、日志和 sqlite-vec 触发阈值。 |
| 后台任务诊断 | 基础能力存在 | 有 health/task state，但没有任务运行记录、失败列表、run id 和重试历史。 |
| FavoritesSync 产品闭环 | 未完成 | 有任务代码，但缺结果页、失败追踪、同步范围、冲突策略和真实验收。 |
| Distribution 控制粒度 | 部分成立 | 后端服务入口收敛，但前端仍有 content-level 操作可能影响多个目标。 |

## 剩余整改方向

1. 移除客户端构建中的后端 API token 注入。
2. 给 browser-auth 路由补 API token 鉴权。
3. 修正 Telegram Bot 空白名单默认 allow-all。
4. 建立统一 SSRF-safe fetcher。
5. 修正本地媒体路径校验和媒体访问鉴权策略。
6. 建立后台任务运行记录。
7. 收藏同步产品化。
8. 分发队列默认改为 item 级控制。
9. 真实平台 integration 建立可重复验收。
