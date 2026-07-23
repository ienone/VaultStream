# 前端文档总览

## 文档状态

active

前端代码位于 `frontend/lib/`，使用 Flutter、Riverpod 和 GoRouter。当前 Root Shell 主入口为动态、收藏库和自动化；设置、任务结果和 Agent 属于工具或深层工作区。

## 页面索引

- `pages/dashboard.md`：动态页当前仍以系统概览为主，目标职责是近期信息流。
- `pages/collection.md`：收藏内容浏览、搜索、筛选和批量维护。
- `pages/content-detail.md`：单条内容阅读、媒体和后处理状态。
- `pages/automation.md`：收藏同步、分发、解析/后处理三类自动化。
- `pages/settings.md`：当前全局低频配置和账号与平台分区；目标账号主流程将迁移到独立账号中心。
- `pages/agent.md`：受控 Agent 会话、工具过程与确认。
- `pages/tasks.md`：后台运行结果统一详情。

## 组件与导航

- `navigation.md`：主导航、工具入口和深链接。
- `components/navigation-shell.md`：Root/Section/Detail 导航容器。
- `components/media-rendering.md`：媒体访问、展示与失败态。
- `components/task-result.md`：任务结果表达边界。

## 页面文档口径

页面文档服务于职责判断、交互审查和回归验收，不充当 Widget 树的文字镜像。每份页面文档只记录：

- 用户来这里完成什么任务，以及明确不承担什么。
- 首屏主要区域、关键动作和重要状态。
- 手机、横屏、平板和桌面的结构性差异。
- 会打开哪些有独立语义的详情页、dialog 或 bottom sheet。
- 读取/写入哪些 API 领域，以及后台任务如何反馈。
- 已确认问题及对应 issue。

以下内容通常不写：具体 Widget 类名、flex 数值、像素宽度、provider 清单、装饰动画参数和内部私有组件名。只有它们构成稳定 contract 或已确认问题根因时才例外记录。

## 当前约束

1. 一个用户职责只能有一个主入口。
2. 不把未实现策略暴露为设置项。
3. UI 不直接散落 API 写操作；由统一控制层编排。
4. 复杂工作流使用独立页面或明确的 adaptive surface。
5. 当前事实与未来计划分开；未来设计进入 `docs/plans/`。

## 当前重点

- 动态页仍有 Dashboard 范围膨胀问题。
- 自动化三域已形成，但详情层级仍需继续拆分。
- 收藏详情转场与媒体失败态仍需整改。
- 当前设置中的账号与平台分区只代表现状；目标账号主流程将按前端 IA 在独立账号中心重建。
