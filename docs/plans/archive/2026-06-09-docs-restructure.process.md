# 文档重构过程

## 状态

complete

## 实际执行记录

- 创建 `frontend/`、`backend/`、`plans/`、`issues/`、`knowledges/`。
- 将已删除旧路径 docs/API.md 迁移为 `backend/api.md`。
- 将已删除旧路径 docs/DATABASE.md 迁移为 `backend/database.md`。
- 将旧 `docs/adapters/*.md` 迁移到 `knowledges/adapters/`。
- 将旧 `docs/eval/*.json` 迁移到 `knowledges/eval/`。
- 将旧 known issue 迁移到 `issues/collection-card-detail-transition.md`。
- 新增前端页面、组件和导航职责文档。
- 新增后端模块职责文档。
- 新增 plans、issues、knowledges 的 README 和汇总文档。
- 删除旧 `architecture/`、`archive/`、`audits/`、`design/`、`validation/`、`adapters/`、`eval/`、`known-issues/` 目录。
- 统一文档状态枚举，现有 issue 状态从 `open` 改为 `active`。
- 补齐前端页面、前端组件、后端模块、知识库文档的 `文档状态` 和模板要求章节。
- 修正 `backend/api.md` OpenAPI 顶部清单，补齐缺失端点并通过校验脚本。
- 重写 `backend/database.md`，以当前 20 张 ORM 表和 FTS5 虚拟表为基线。
- 更新过期的收藏详情转场 issue、Twitter adapter 和 Universal adapter 知识库文档。
- 同步前端页面文档口径，要求 `当前界面内容` 记录当前界面区域、布局/弹性布局、响应式断点、弹出界面和临时状态。

## 偏离计划

- 目录名采用用户原始提案 `knowledges/`，未改为 `knowledge/`。
- 原 plan 将“不重新生成 OpenAPI”列为非目标；实际执行中没有重新生成整份 API 正文，但修正了 OpenAPI 顶部端点清单，并运行校验脚本确认其覆盖当前 FastAPI schema。

## 验证结果

- `docs/` 顶层现只保留 `README.md`、`frontend/`、`backend/`、`plans/`、`issues/`、`knowledges/`。
- `rg --files docs` 已确认 adapters 文档迁移到 `docs/knowledges/adapters/`。
- `rg --files docs` 已确认 eval 数据迁移到 `docs/knowledges/eval/`。
- `.venv\Scripts\python.exe scripts\check_openapi_docs.py docs\backend\api.md` 通过，覆盖 127 个端点。
- `rg --files-without-match "## (文档状态|状态)" docs -g "*.md"` 无缺失输出。
- `rg "__tablename__" backend\app\models` 统计到 20 张 ORM 表，已在 `backend/database.md` 覆盖。
- 未运行业务测试；本次只重构文档。

## 后续问题

- API 文档已完成本轮 OpenAPI 一致性校验；后续需要纳入维护流程或 CI，避免端点清单再次漂移。
- 旧审计原文删除后，细节需要通过 git 历史追溯。
