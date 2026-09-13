# VaultStream 文档入口

文档区分产品目标、当前实现、待解决问题和研究证据。代码与可重复验证结果是当前事实来源；发现文档过时应直接修正，不为旧描述保留兼容实现。

## 从哪里开始

| 任务 | 入口 |
| --- | --- |
| 产品目的与能力规划 | [系统构想](plans/2026-07-15-vaultstream-system-concept.plan.md) |
| 前端信息架构与体验 | [前端设计方案](plans/2026-06-10-frontend-information-architecture-redesign.plan.md) |
| 整体重审、完成度与实施取舍 | [2026-09-14 产品与架构改进方案](plans/2026-09-14-product-architecture-review.plan.md) |
| 前端实现 | [前端索引](frontend/README.md)，再按需读页面、组件与导航 |
| 后端实现 | [后端索引](backend/README.md)，再按需读模块、API 与数据库 |
| 当前问题 | [问题目录](issues/README.md) |
| 进行中的实施 | [计划索引](plans/README.md) |
| 平台接入资料 | [Adapter 知识](knowledges/adapters/README.md) |
| 页面截图与体验审校 | [2026-09-13 UI 审校](knowledges/ui-review-2026-09-13/README.md) |

## 目录职责

- `frontend/`、`backend/`：当前实现和稳定契约；避免逐次追加修复日志。
- `issues/`：需要继续处理的问题；已解决的普通问题依赖 Git 历史，不必逐个归档。
- `plans/`：产品方案与确需跨会话推进的实施计划。目标设计不等于已经实现。
- `knowledges/`：平台资料、外部参考与仍有用途的评估证据。
- [已关闭问题的历史决策](issues/archive/README.md)。

## 维护方式

按任务读取相关内容，不默认遍历全部文档。小型修复不另建 plan/process；多轮实施需要接续时，记录当前进展、关键取舍和剩余问题即可。产品构想不需要配套过程文件。

更新时直接整理原文，清除失效状态、重复摘要、旧命令输出和已被当前文档吸收的说明。完成的 plan/process 成对收拢或删除，未解决问题不能随日志一起丢弃。截图保留实际分析或后续工作需要的证据，旧版本无引用素材及时清理。

索引只负责导航。保留必要的实现、实测和未验证边界，不用历史测试数量代表当前质量。移动或删除文件后同步检查链接。
