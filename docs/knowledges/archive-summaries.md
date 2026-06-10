# 旧文档归档汇总

## 文档状态

active

## 适用范围

本文汇总旧 `docs/archive/`、`docs/audits/`、`docs/architecture/`、`docs/design/`、`docs/validation/` 中仍有参考价值的信息。旧目录已经在本次文档重构中移除，本文只保留索引级摘要，不替代当前 `frontend/`、`backend/`、`plans/`、`issues/` 下的权威文档。

## 背景

旧文档来自多个阶段的设计、审计、验证和路线图记录，粒度和事实状态不一致。为了避免旧结论继续污染当前实现说明，重构后将可执行的当前事实迁移到对应模块文档，将仍有价值但不再作为规范的材料沉淀到本知识库摘要中。

## 当前事实

旧文档中的前后端结构、产品审计、导航设计、自动化设计和验收口径已经被拆分到当前目录结构。仍需追溯原文时，应通过 git 历史查看被移除文件，而不是恢复旧目录作为并行文档源。

## 与代码的关系

本文不直接描述单个代码模块的实现细节。与代码相关的当前事实应以 `../backend/`、`../frontend/` 和相关 issue/plan 文档为准；本文只记录旧文档结论被迁移到哪里，以及哪些历史判断仍值得保留。

## 使用方式

开发前如果遇到“旧文档曾经如何描述某个方向”的问题，先查本文确认是否已有迁移目标；需要落地实现时，再进入对应 frontend/backend/plan/issue 文档补充当前设计和验收口径。

## 已知限制

本文是人工摘要，不能覆盖旧文档中的全部细节。旧文档可能包含已经过期的代码路径、产品假设和验证结果；引用时必须回到当前代码和当前文档重新确认。

本文件汇总旧 `docs/archive/`、`docs/audits/`、`docs/architecture/`、`docs/design/`、`docs/validation/` 中仍有价值的信息。旧目录在本次重构后移除。

## 旧架构文档

旧 `architecture/BACKEND.md` 的后端总体结构已拆入 `../backend/README.md` 和 `../backend/modules/`。旧 `architecture/ROADMAP_V2.md` 的路线图已拆为 issues 和 plans。旧 `architecture/VECTOR_SEARCH_EVALUATION.md` 的结论归入 `../backend/modules/search-rag.md`。

## 旧审计文档

2026-06-05 产品体验与安全审计的主要结论：

- 后台任务缺少统一可观测性。
- 收藏同步仍需产品化。
- 平台账号健康状态分散。
- LLM 配置碎片化。
- 错误提示不够产品化。
- 分发、发现、后处理等前后端控制边界需要收敛。

2026-06-06 前端协同审计的主要结论：

- 前端控制面与后端自动行为不一致。
- 收藏卡片到详情页转场仍有问题。
- 复杂工作流不应继续塞进弹窗。
- 二级界面和结果页需要收敛。
- 设置与前端功能面不完整。

2026-06-09 前端 AI 生成代码污染审校的主要结论：

- 账号中心职责重复。
- 自动化页职责过宽。
- 巨型组件和直接 API 调用严重污染前端。
- 共享 `Hero` 转场、侧边栏布局和图片代理造成用户可见问题。

这些问题已拆分到：

- `../issues/frontend-account-entry-responsibility-duplication.md`
- `../issues/frontend-automation-page-responsibility-overload.md`
- `../issues/frontend-ui-layer-api-write-boundary.md`
- `../issues/frontend-navigation-utility-group-layout.md`
- `../issues/frontend-control-policy-gaps.md`
- `../issues/media-proxy-image-access.md`
- `../issues/collection-card-detail-transition.md`

## 旧设计和计划

旧产品导航与自动化设计、执行步骤总表已汇总到：

- `../plans/archive/2026-06-06-product-navigation-and-automation-summary.md`

仍然有效的方向：

- 主导航只保留核心业务入口。
- 设置页降级为低频配置。
- 账号中心唯一化。
- 收藏同步产品化。
- 动态页统计按业务域拆分。

## 旧验收文档

旧 `validation/product-acceptance.md` 的验收口径保留为原则：

- 后端使用 `.venv\Scripts\python.exe -m pytest backend/tests -q -m "not integration"`。
- 前端使用 `flutter analyze` 和 `flutter test`。
- 产品验收必须覆盖核心页面、任务结果、失败态和移动/桌面断点。

## 历史归档

旧 `archive/` 中的 2026-04/2026-05 审计、历史计划、legacy notes 只保留摘要。需要原文时通过 git 历史追溯。
