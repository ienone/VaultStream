# 功能差距与路线图对齐

## README/路线图能力状态

| 能力 | 当前观察 | 差距 |
| --- | --- | --- |
| SQLite FTS5 | 文档声明存在；当前 DB 无 `contents_fts` | 需要 migration/backfill/health check |
| RAG semantic search | `/search/semantic` 和 embedding service 已有 | 向量 JSON O(N)，Discovery 未统一索引，summary 测试失效 |
| Agent | `/agent/tools`、`/agent/run`、`/agent/ws` 已有 | 当前是关键词 tool router，缺少模型推理、session、审计审批 |
| Favorites sync | 后端有 `/favorites-sync/status`、`/favorites-sync/sync` | API 文档未同步，测试覆盖需确认 |
| Distribution queue | enqueue/worker/repush 已有 | 文档未覆盖 repush；自动审批入口重复 |
| Predictive back gesture | README roadmap 提及 | 未在本次静态审计中确认实现 |
| RSS/Atom | RSS adapter 和 discovery RSS 存在 | 解析 adapter 生命周期与 Discovery 入库后处理需收敛 |
| AI patrol | `PatrolService` 和 Discovery 调用存在 | 配置、测试、指标需补齐 |
| Telegram deep integration | bot/chat/distribution 路径存在 | token/日志/外部服务 URL 安全基线需补强 |

## API 文档缺口

实际路由包含但 `docs/API.md` 未充分覆盖：

- `/agent/tools`
- `/agent/tools/{tool_name}/invoke`
- `/agent/run`
- `/agent/ws`
- `/favorites-sync/status`
- `/favorites-sync/sync`
- discovery 相关多端点
- distribution queue 的 `repush-now` 和 batch repush

建议：自动导出 OpenAPI JSON，并用脚本比对 `docs/API.md` 的 endpoint 清单，避免手写文档继续漂移。

## 数据库文档缺口

`docs/DATABASE.md` 最大问题是 FTS5 声明与当前实现不一致。另一个问题是迁移机制描述偏理想化：实际代码更接近 `Base.metadata.create_all` + 启动时兼容逻辑。建议：

- 短期修正文档，标注 FTS 当前状态。
- 中期引入 Alembic 或明确的 schema migration runner。
- 长期将 `schema_version` 纳入健康检查和升级脚本。

## Agent 路线图差距

当前 Agent 逻辑：

- `service.py` 使用关键词/正则推断工具。
- `router.py` 支持直接 invoke tool、run message、websocket stream。
- stream 是把 JSON 结果按 256 字符分块发送。

如要达到路线图中的 Agent，应补齐：

1. LLM planner 或明确不做 LLM agent。
2. session/message history。
3. tool permission/approval。
4. tool result schema 和错误码。
5. 前端 typed rendering。
6. 审计日志。

否则应在产品文案中称为“自动化工具助手”或“命令路由器”。

## RAG 路线图差距

当前 RAG/semantic search 已有骨架，但还缺：

1. 可靠 embedding 索引触发机制。
2. 缺失 FTS 时的可观测降级。
3. 向量索引或候选裁剪。
4. provider 配置统一。
5. summary/chunk schema 测试。

## 发布路线图差距

Release workflow 能构建产物，但不像生产发布门禁：

- 没有测试 gate。
- 没有依赖漏洞 gate。
- 没有 debug flag gate。
- 没有 Docker scan。
- 没有数据库迁移校验。

建议先把 release 定义为“构建产物”，不要称为“质量认证发布”；等门禁补齐后再提升发布等级。
