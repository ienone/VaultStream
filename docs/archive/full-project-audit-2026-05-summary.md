# 2026-05 全项目审计摘要

> 来源：旧 `full_project_audit_2026-05-13/` 目录。  
> 当前状态：历史审计浓缩版。已由当前综合审计确认解决的事项不再列为待修；剩余项只保留仍影响路线图、验收或风险判断的部分。

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

## 仍影响当前工作的遗留风险

| 主题 | 当前状态 | 说明 |
| --- | --- | --- |
| 真实平台 integration 测试 | 未稳定 | 非 integration 通过不能证明知乎、小红书、真实 LLM 等外部链路稳定。 |
| API token 构建注入 | 未确认清零 | manual build workflow 仍需按当前 workflow 和产物策略复核，避免把共享后端 token 编译进客户端产物。 |
| 向量检索性能 | 短期缓解 | 仍是 JSON 向量表和应用层计算，只是增加扫描上限、日志和 sqlite-vec 触发阈值。 |
| 后台任务诊断 | 部分解决 | 已有最近运行记录、`run_id`、动态页时间线和若干重试入口；仍缺更完整事件流、独立结果页、按异常项聚焦的恢复入口和跨链路运维面板。 |
| FavoritesSync 产品闭环 | 部分解决 | 已有运行记录、预览、结构化结果摘要、失败诊断、失败 run/单条/批量失败项重试和重复策略配置；仍缺收藏夹/分组范围、完整失败列表、独立结果页、候选进入收件箱以及取消收藏/删除/冲突策略。 |
| Distribution 控制粒度 | 基本收敛，需守边界 | 前端队列主体已使用 item 级接口，后端仍保留 content-level 兼容/批量接口；后续需要继续避免普通单项操作误用 content-level path。 |

## 已由当前综合审计确认不再作为待修项保留

- 图片代理、本地媒体、归档媒体和通用解析 SSRF 风险已接入 `safe_fetch` 或本地路径祖先校验，并有相关测试覆盖。
- `/api/v1/browser-auth` router 已要求 API token。
- Telegram Bot 白名单为空时已 fail closed，管理员仍保留普通命令权限。
- 本地归档媒体 API 已要求 API token，旧的无鉴权 `/media` StaticFiles 挂载已移除。

## 剩余整改方向

1. 复核并移除客户端构建中的后端 API token 注入风险。
2. 继续扩展后台任务运行记录、独立结果页、失败列表和恢复入口。
3. 收藏同步继续产品化：范围、策略、候选审核、完整结果和真实验收。
4. 持续保持分发队列默认 item 级控制，并限制 content-level 接口的 UI 使用场景。
5. 真实平台 integration 建立可重复验收。
6. 新增服务端 URL 获取入口时复用现有 safe fetch/path 校验策略，避免回归。
