# 文档重构计划

## 状态

complete

## 背景

旧 `docs/` 中 API、数据库、架构、设计、审计、已知问题、验收和归档材料混放。agent 容易把历史设想当作当前实现，把问题清单当作计划，或把知识库文档当成待办。

## 目标

- 只保留新的顶层目录：`frontend/`、`backend/`、`plans/`、`issues/`、`knowledges/`。
- 将 `adapters/` 移入 `knowledges/adapters/`。
- 将 API 和数据库文档迁入 `backend/`。
- 将前端页面职责、后端模块职责、问题、计划和知识库分开。
- 把旧审计和设计文档汇总进新 issues/plans/knowledge，而不是继续保留旧目录。

## 非目标

- 不修改业务代码。
- 不修复前端污染问题本身。
- 不重新生成 OpenAPI。
- 不重写平台适配器知识内容。

## 关联文档

- `../frontend/README.md`
- `../backend/README.md`
- `../../issues/README.md`
- `../issues/frontend-control-policy-gaps.md`
- `../knowledges/archive-summaries.md`

## 变更范围

- `docs/` 文档目录。
- 不触碰 `frontend/`、`backend/app/`、`backend/tests/`、`frontend/test/`。

## 实施步骤

1. 创建新目录结构。
2. 迁移 API、数据库、adapter 和 eval 数据。
3. 写前端页面职责文档。
4. 写后端模块职责文档。
5. 汇总旧审计为 issues。
6. 汇总旧计划和历史归档为 plans/archive 或 knowledges。
7. 删除旧目录。
8. 校验 `docs/` 只剩新顶层目录。

## 验收标准

- `docs/` 顶层只包含 `README.md` 和五个新目录。
- adapters 文档只存在于 `docs/knowledges/adapters/`。
- 前端每个主要页面都有职责文档。
- 后端主要模块都有职责、测试和 API 章节。
- 旧审计结论可在 `issues/` 或 `knowledges/` 找到摘要。

## 风险

- 旧长文档被汇总后会丢失部分细节；需要通过 git 历史追溯原文。
- API 文档仍是手写清单，可能与代码漂移；后续应从 OpenAPI 自动生成或定期校验。
