# 历史计划摘要

> 来源：旧 `plans/` 目录和 `architecture/` 下已归档的计划文档。  
> 当前状态：历史参考，具体执行以当前代码和综合审计为准。

## Discovery 相关计划

历史计划曾设想 Discovery 支持 RSS、HackerNews、Reddit、GitHub、Telegram 等来源，并通过 AI 巡逻、事件聚合、缓冲区分拣和一键收藏进入主库。

当前需要纠正的边界：

- 当前实际稳定实现重点是 RSS 和 Telegram Channel。
- HackerNews、Reddit、GitHub 等不应在普通用户配置流里表现为已完成。
- 发现源同步返回 202 但缺少 run id、进度和最终结果。
- AI 巡逻评分存在，但用户缺少解释、阈值理解和失败反馈。

## RAG 与向量检索计划

历史计划曾提出更激进的 RAG 优化，包括摘要后再 embedding、结构化 RAG payload、NumPy 加速、sqlite-vec 或 Faiss 等。

当前采用的实际边界：

- 短期继续使用 `content_embeddings` JSON 表。
- 通过 `embedding_search_max_rows`、候选限制和日志控制成本。
- 达到 `VECTOR_SEARCH_EVALUATION.md` 的阈值后，再试点 sqlite-vec。
- 不能把当前状态称为“向量检索性能彻底修复”。

## 数据库清理计划

历史 DB 清理计划关注 schema 漂移、Bot 配置收敛、content embeddings 表结构、FTS 和迁移补齐。

当前保留的原则：

- 数据库文档只能说明当前结构，迁移状态仍应由代码和脚本验证。
- 对旧库兼容逻辑要尽量集中在初始化/迁移路径。
- 任何删除字段或表的建议都必须确认历史数据和导出/备份路径。

## HTTP/QR Auth 计划

历史小红书 QR auth 计划描述了二维码会话、扫码确认、Cookie 收集、风控 captcha 状态等。

当前仍需关注：

- Browser-auth 路由已在 router 级别要求 API token，并有对应 API 测试；历史“需要鉴权”的说法不再作为待修项保留。
- 账号健康状态应统一展示，而不是散落在连接页、设置页、收藏同步和诊断页。
- 平台风控和登录失效需要用户可行动的错误提示。

## CLI 与集成计划

旧 CLI 集成计划更多是历史任务跟踪。已确认完成的历史 bugfix 不再保留为当前文档内容。

仍有价值的原则：

- 真实平台能力必须用可重复验收验证。
- 文档中的“Done”不能代替当前代码和测试。
- 自动化入口应给用户可追踪结果，而不是只返回“已触发”。
