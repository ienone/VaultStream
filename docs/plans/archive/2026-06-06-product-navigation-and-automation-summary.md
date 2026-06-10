# 2026-06-06 产品导航与自动化设计归档摘要

## 状态

archived

## 来源

汇总自旧 `docs/design/product-navigation-and-automation.md` 和 `docs/design/implementation-steps-2026-06-06.md`。

## 核心设计方向

- 主导航应聚焦动态、收藏库、收件箱、自动化。
- 设置入口应作为低频配置，不承载复杂工作流。
- 收藏同步需要产品化，包含账号状态、同步配置、预览、运行记录和失败重试。
- 动态页不应长期承载所有统计；统计应按业务归属拆到收藏库、收件箱和自动化。
- Agent/RAG 入口应暂缓扩张，先保证基础产品可信。

## 已被当前文档吸收

- 前端页面职责已拆入 `../../frontend/pages/`。
- 自动化、账号中心、收藏同步的职责冲突已分别记录到 `../../issues/frontend-automation-page-responsibility-overload.md`、`../../issues/frontend-account-entry-responsibility-duplication.md` 和 `../../issues/frontend-favorites-sync-placeholder-strategy-leak.md`。
- 动态页统计拆分问题已记录到 `../../frontend/pages/dashboard.md` 和 `../../frontend/pages/collection.md`。

## 未完成事项

- 动态页统计拆分仍未完成。
- 收藏同步入口仍需收敛。
- 账号中心仍需成为唯一平台账号主入口。
- 复杂弹窗仍需迁移到独立页面或统一 task surface。
