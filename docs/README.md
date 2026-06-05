# VaultStream 文档索引

> 最后整理：2026-06-05  
> 使用原则：当前状态以代码、测试和 `docs/audits/2026-06-05-current-product-security-audit.md` 为准。已确认完成的历史事项已从当前文档中移除；仍保留的历史状态描述需要按当前代码重新验证。

## 当前必读

- [audits/2026-06-05-current-product-security-audit.md](./audits/2026-06-05-current-product-security-audit.md) - 当前产品体验、功能缺口、前后端控制边界、测试可信度和安全扫描。
- [design/product-navigation-and-automation.md](./design/product-navigation-and-automation.md) - 主导航、收藏同步、账号中心、Agent/RAG、时间线和自动化体验设计。
- [architecture/ROADMAP_V2.md](./architecture/ROADMAP_V2.md) - 当前开发方向和风险排序。
- [architecture/BACKEND.md](./architecture/BACKEND.md) - 后端架构、模块边界和主要数据流。
- [API.md](./API.md) - API 端点和请求/响应约定。
- [DATABASE.md](./DATABASE.md) - 数据库结构、FTS、语义索引和迁移说明。
- [architecture/VECTOR_SEARCH_EVALUATION.md](./architecture/VECTOR_SEARCH_EVALUATION.md) - 语义检索当前方案与 sqlite-vec 试点阈值。
- [validation/product-acceptance.md](./validation/product-acceptance.md) - 产品级冒烟检查、真实平台端到端验收和测试结论口径。

## 平台适配器

- [adapters/UNIVERSAL_ADAPTER.md](./adapters/UNIVERSAL_ADAPTER.md)
- [adapters/BILIBILI_ADAPTER.md](./adapters/BILIBILI_ADAPTER.md)
- [adapters/TWITTER_ADAPTER.md](./adapters/TWITTER_ADAPTER.md)
- [adapters/WEIBO_ADAPTER.md](./adapters/WEIBO_ADAPTER.md)
- [adapters/XIAOHONGSHU_ADAPTER.md](./adapters/XIAOHONGSHU_ADAPTER.md)
- [adapters/ZHIHU_ADAPTER.md](./adapters/ZHIHU_ADAPTER.md)

## 当前已知问题

- [known-issues/collection-card-detail-transition.md](./known-issues/collection-card-detail-transition.md) - 收藏卡片到详情页 shared transition 的剩余视觉验证。
- [known-issues/discovery-detail-top-overlap.md](./known-issues/discovery-detail-top-overlap.md) - Discovery 详情页顶部遮挡问题。

## 评估数据

- [eval/rag_ground_truth.json](./eval/rag_ground_truth.json)
- [eval/rag_recall_report.json](./eval/rag_recall_report.json)

## 归档

历史审计、旧计划和已归档问题已浓缩到 [archive/](./archive/)。

这些文件保留用于追溯上下文，不代表当前实现状态：

- [archive/architecture-audit-2026-04-summary.md](./archive/architecture-audit-2026-04-summary.md)
- [archive/full-project-audit-2026-05-summary.md](./archive/full-project-audit-2026-05-summary.md)
- [archive/historical-plans-summary.md](./archive/historical-plans-summary.md)
- [archive/legacy-notes-summary.md](./archive/legacy-notes-summary.md)
