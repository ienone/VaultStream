# VaultStream 后续开发总路线

## 状态

active

## 文档职责

本文是 VaultStream 唯一的全局开发顺序来源。理想产品能力由 `./2026-07-15-vaultstream-system-concept.plan.md` 定义；本文只保留阶段依赖、出口条件、问题归属和待建立的专项计划，不重复产品规格。

## 当前判断

VaultStream 已具备相当规模。2026-07-24 当前基线中，Flutter analyze/test、后端非集成测试、OpenAPI 文档和 schema gate 均可通过，但干净环境依赖准备仍未完成验证，部分 issue 已落后于代码；日常主链仍受职责污染、策略边界、媒体失败和界面失焦影响。后续不能按功能数量并行扩张，应先校准可信基线，再完成“捕获—存档—找到—阅读/播放”的稳定闭环，最后扩展主动探索和复杂 Agent。

## 路线原则

- 先让用户愿意日常使用，再扩大能力覆盖。
- 数据安全、API contract 和副作用策略先于新入口。
- 共享领域能力先于 Agent 编排。
- 每次只推进可独立验收的垂直切片。
- 新职责稳定后删除旧路径，不保留长期 fallback。
- 前一阶段未达到出口条件时，不进入依赖它的复杂阶段。

## 阶段路线

| 阶段 | 目标 | 主要工作 | 阶段出口 |
| --- | --- | --- | --- |
| 0. 可信基线 | 恢复可复现、可安全修改的基础 | issue 复核、测试/CI、schema、动作 API、task contract、策略边界 | 核心检查可重复；文档与代码一致；关键数据和副作用有 contract |
| 1. 日常收藏主链 | 让保存、查找和阅读首先变得好用 | 内容模板与保留策略、图片链路、Material 3 Expressive 基线、收藏/详情/动态/任务体验 | 普通链接可形成可读存档；核心页面多断点可用；人工修改不被覆盖 |
| 2. 捕获与归档入口 | 降低保存成本并统一入口语义 | 应用内捕获、Android 分享、Bot/桌面入口、重复与来源关系、媒体保留 | 至少一个系统入口和一个消息或桌面入口完成端到端验收 |
| 3. 富媒体体验 | 让文档、音频和视频成为可消费知识 | 图集/文档模板、全局播放器、字幕章节、仅音频、画中画、系统媒体会话 | 离开详情仍可播放；页码和时间点可搜索引用；横竖屏稳定 |
| 4. 搜索与模型治理 | 建立可靠检索、RAG 和成本控制 | 混合检索、证据定位、评估集、统一模型调用、供应商缓存、调用日志 | 回答可定位证据；内容未变化不重复处理；调用成本可审计 |
| 5. 主动探索与事件 | 减少重复阅读和信息过载 | 少量来源接入、去重聚类、价值理由、事件视图、分级通知 | 多来源不重复占注意力；事件可修正；高价值变化才通知 |
| 6. Agent 与受控行动 | 用自然语言组合已经稳定的能力 | 场景化 Agent、typed tools、权限确认、审计、取消和恢复 | Agent 与常规 UI 使用同一能力，不能绕过用户策略 |
| 7. 规模化远景 | 只在真实需求出现后扩展边界 | 账号/工作空间、性能测量、单模块 Rust 实验 | 有真实需求或性能证据；迁移后删除旧双路径 |

## 当前问题归属

### 第零阶段：基线、contract 与策略

- `../issues/frontend-agent-page-controller-and-sse-boundary.md`
- `../issues/backend-test-suite-value-density.md`
- `../issues/backend-ci-environment-reproducibility.md`
- `../issues/backend-schema-gate-database-doc-drift.md`
- `../issues/backend-diagnostic-api-contract-is-inline.md`
- `../issues/backend-system-router-boundary-pollution.md`
- `../issues/backend-agent-api-bridge-policy-bypass.md`
- `../issues/backend-bot-config-router-side-effects.md`
- `../issues/favorites-sync-retry-policy-gap.md`
- `../issues/frontend-control-policy-gaps.md`
- `../issues/frontend-ui-layer-api-write-boundary.md`
- `../issues/frontend-post-processing-panel-side-effects.md`
- `../issues/task-run-result-contract-missing.md`

### 第一阶段：界面与日常内容体验

- `../issues/frontend-automation-page-responsibility-overload.md`
- `../issues/frontend-dashboard-scope-creep.md`
- `../issues/frontend-material3-expressive-design-system-gap.md`
- `../issues/media-proxy-image-access.md`

后续阶段的新问题只在真实实现或专项调研开始后建立，避免提前堆积远期 issue。

## 专项 Plan 队列

| 顺序 | 主题 | 前置条件 |
| --- | --- | --- |
| 0.1 | 当前质量基线与 active issue 事实复核 | 无 |
| 0.2 | 测试体系与 CI 可复现性 | 0.1 |
| 0.3 | 数据库 schema 与迁移基线 | 0.1 |
| 0.4 | 动作 API、task run 与自动化策略 contract | 0.1 |
| 1.1 | 内容模型、模板与保留策略 | 0.3 |
| 1.2 | Material 3 Expressive 设计系统与 UI 审计 | 0.1 |
| 1.3 | 收藏库、详情与动态主链 | 0.4、1.1、1.2 |
| 2.1 | 统一捕获与多入口 | 1.1、1.3 |
| 3.1 | 富媒体归档与全局播放 | 1.1、1.2 |
| 4.1 | 混合搜索与 RAG 评估 | 1.1 |
| 4.2 | 模型调用与 token 成本治理 | 0.4、4.1 |
| 5.1 | 主动探索与信息降噪 | 4.1、4.2 |
| 5.2 | 事件聚合与通知 | 5.1 |
| 6.1 | Agent 能力与安全编排 | 0.4、4.1、4.2 |
| 7.1 | 账号/工作空间演进 | 真实多用户需求 |
| 7.2 | Rust 可行性实验 | 明确性能瓶颈 |

未进入当前阶段的主题只保留在本队列，不提前建立实现细节文档。

## 当前第一批次

只启动第零阶段：

1. 复核 active issue 与当前代码，归档已解决项、改写失真项并清理现状文档漂移。
2. 启动测试/CI 计划的风险映射与干净环境复现；当前本地测试通过不替代依赖可复现性结论。
3. 为 schema/migration 和动作 API/task/policy 分别建立可执行专项计划。
4. Agent 页面不再作为构建阻断；其 controller、SSE contract 和 UI 层职责问题进入后续可验收切片。
5. 内容模板与 Material 3 UI 审计只准备范围，不同时实施大规模重构。

## Plan 启动规则

专项计划开始前必须明确：

- 解决的用户任务或 issue。
- 当前代码、数据和验证事实。
- 变更范围、外部副作用和回滚边界。
- 前置计划是否满足。
- 可复现的验收方式。
- 完成后删除的旧实现和旧文档。

一个执行周期只保持少量相互依赖的计划处于实施状态。

## 待确认决策

- 第一条“每天可用”主链是否必须包含 Android 分享。
- 首批模板和代表性验收样本范围。
- Android 分享、Telegram Bot、QQ Bot 与桌面入口顺序。
- 网页、图片和音视频的默认本地保留策略。
- 音频播放是否提前进入第一阶段。
- 当前支持的 Python、Flutter 和部署环境矩阵。

## 总体验收

- 用户能方便捕获、稳定存档、快速找到并舒适阅读或播放内容。
- 来源、版本、媒体和人工修订不被自动流程破坏。
- 搜索、RAG、事件和 Agent 能回到真实证据。
- 自动化、Bot 和 Agent 遵守同一用户策略并留下审计。
- 模型结果可复用，供应商缓存与成本可观察。
- 每阶段具有可重复出口，不再通过无监督大规模修改推进。

## 风险

- 第零阶段必须聚焦阻断主链和高风险问题，避免无限技术清债。
- UI 与内容模型不能脱节并行。
- 过早接入大量平台会挤压核心存档体验。
- 过早建设复杂 Agent 会放大 contract、策略和成本问题。
- 远期计划不得提前写入容易漂移的实现细节。
