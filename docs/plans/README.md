# Plans

## 文档状态

active

本目录保存产品构想、开发总路线和成规模实施计划。计划不是当前实现；当前事实仍以代码、验证结果和 `docs/frontend/`、`docs/backend/` 为准。

## 权威层级

1. `2026-07-15-vaultstream-system-concept.plan.md`：回答理想产品是什么。
2. `2026-07-17-vaultstream-development-roadmap.plan.md`：回答先做什么、后做什么。
3. 领域专项 plan：回答某一阶段怎样实施。
4. process：仅记录已启动长期计划的关键执行进展。

专项计划不得另建与总路线冲突的全局阶段顺序。

## 当前计划

| 文档 | 状态 | 角色 | Process |
| --- | --- | --- | --- |
| `2026-07-15-vaultstream-system-concept.plan.md` | active | 产品愿景与理想形态 | 不需要 |
| `2026-07-17-vaultstream-development-roadmap.plan.md` | active | 唯一开发顺序与阶段出口 | 不需要 |
| `2026-06-10-frontend-information-architecture-redesign.plan.md` | active | 前端总体构想与体验设计方案 | 不需要 |
| `2026-07-17-test-and-ci-reliability.plan.md` | active | 第零阶段测试与 CI 专项，尚未启动 | 启动后按需创建 |

## 何时创建 Plan

满足任一条件时创建：

- 跨多个模块或前后端。
- 涉及数据迁移、外部副作用、安全或高回归风险。
- 需要多轮、跨会话推进。
- 存在需要用户确认的范围、顺序或取舍。

小型修复、单文件调整和明确缺陷通常使用 issue、提交或 PR，不额外创建 plan。

## 何时创建 Process

只有计划已经启动，且需要跨会话交接、记录关键决策或阶段验证时才创建同名 process。

- Draft plan 不创建 process。
- 已确认但尚未启动的 active plan 不要求 process。
- 短期一次性完成的 plan 可把最终验证直接写回 plan 后归档。
- Process 不记录完整命令输出和逐文件清单。

## 完成与归档

- 完成前记录验收结论和未验证项。
- 有长期决策价值的 plan/process 一起移入 `archive/`。
- 已被新文档吸收、没有长期价值的计划可以删除并依赖 Git 历史。
