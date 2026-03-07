# 🚀 Discovery & Patrol 前端实现步骤

> 依据文档：`docs/architecture/DISCOVERY_PATROL_INTEGRATION.md` 第 5 章（前端设计方案）
>
> 目标：规划接下来 Flutter 前端需要新增或修改的内容，并给出可执行的 Step 清单。

## 0. 当前状态快照（2026-03-07）

### 已具备
- 后端已提供基础 Discovery API（`/api/v1/discovery/items`、`/api/v1/discovery/sources`、`/api/v1/discovery/settings`、`/api/v1/discovery/stats`）。
- 前端已具备可复用的列表/筛选/批量模式（`collection` 模块）和设置页骨架（`settings` 模块）。
- `ContentDetail` 已支持 `context_data`，可承接后续 `source_links` 展示。

### 主要缺口
- 前端尚无 `features/discovery/` 模块，无独立探索页与路由入口。
- `AutomationTab` 中 AI 发现仍为占位文案，未对接 `discovery/settings` 与 `discovery/sources`。
- 设计要求的 Telegram 双开关（`is_monitoring`/`is_push_target`）当前前后端接口链路未完整打通。
- 设计中的聚合组交互（merge/split/来源展开）对应 API 尚未全部落地。

---

## 1. 实施顺序总览

```
Sprint 0:
  Step A (接口契约对齐)

Sprint 1:
  Step B (Discovery 基础数据层)
    -> Step C (导航与页面骨架)
    -> Step D (探索列表 + 详情 + 单条操作)

Sprint 2:
  Step E (批量操作 + 筛选完善)
  + Step F (设置中心扩展)

Sprint 3:
  Step G (主库详情 source_links 适配)
  + Step G2 (Dashboard 发现概览)
  + Step H (测试与验收)

Phase 2:
  Step I (聚合组 merge/split 高级交互 + enrichment 展示)
```

---

## 2. 详细 Step 清单

## Step A: 接口契约对齐（Sprint 0 前置）

> 不属于 UI 编码本身，但会直接阻塞前端开发。前后端协作完成。

| # | 子任务 | 影响文件 | 说明 | 状态 |
|---|---|---|---|---|
| A.1 | Discovery 列表查询参数对齐 | `backend/app/routers/discovery.py` | 统一 `sort_by/sort_order` 与 `tag/tags` 约定，避免前端兼容分支过多 | ⏳ |
| A.2 | BotChat 响应补字段 | `backend/app/schemas/bot.py`, `backend/app/routers/bot_management.py` | 在 `BotChatResponse` 返回 `is_monitoring`、`is_push_target` | ⏳ |

**完成标准**
- 前端能基于单一契约实现，不需要在 provider 中写多套 fallback 字段映射。

> ℹ️ 原 A.3（Phase 2/3 端点占位 501）移除——对 Phase 1 MVP 无实际阻塞，Phase 2 实施时再补齐即可。

---

## Step B: Discovery 基础数据层（Model + Provider）

| # | 子任务 | 涉及文件（新增/修改） | 说明 | 状态 |
|---|---|---|---|---|
| B.1 | 新增 Discovery 数据模型 | `frontend/lib/features/discovery/models/discovery_models.dart` | 建立 `DiscoveryItem/Source/Settings/Stats` 结构与 JSON 序列化 | ✅ |
| B.2 | 新增 Discovery Provider | `frontend/lib/features/discovery/providers/discovery_items_provider.dart` 等 | 对接 `/discovery/items`、`/sources`、`/settings`、`/stats` | ✅ |
| B.3 | 新增筛选状态 | `frontend/lib/features/discovery/providers/discovery_filter_provider.dart` | 承载 state/source/score/tags/q/date 等查询条件 | ✅ |
| B.4 | 新增批量选择状态 | `frontend/lib/features/discovery/providers/discovery_selection_provider.dart` | 复用 `collection` 的多选交互模式，支持 bulk promote/ignore | ✅ |

**完成标准**
- 在不接 UI 的情况下，Provider 可独立完成列表加载、筛选参数拼装、单条操作和批量操作。

---

## Step C: 路由与导航接入

| # | 子任务 | 涉及文件（新增/修改） | 说明 | 状态 |
|---|---|---|---|---|
| C.1 | 增加 Discovery 路由 | `frontend/lib/routing/app_router.dart` | 新增 `/discovery` 路由（必要时附详情子路由） | ✅ |
| C.2 | 导航栏增加入口 | `frontend/lib/layout/app_shell.dart` | Mobile `NavigationBar` + Desktop `NavigationRail` 增加探索入口 | ✅ |
| C.3 | 导航索引回归检查 | `frontend/lib/layout/app_shell.dart` | 处理分支 index 变化对 `collection` 过滤清理逻辑的影响 | ✅ |

**完成标准**
- 桌面/移动端均可从一级导航进入 Discovery 页面。

---

## Step D: 探索页面 MVP（列表 + 详情 + 单条操作）

| # | 子任务 | 涉及文件（新增/修改） | 说明 | 状态 |
|---|---|---|---|---|
| D.1 | 新建 Discovery 页面骨架 | `frontend/lib/features/discovery/discovery_page.dart` | 实现横竖屏自适应容器 | ✅ |
| D.2 | 实现列表卡片 | `frontend/lib/features/discovery/widgets/discovery_item_card.dart` | 展示评分、标题、来源、时间、摘要、多源徽章 | ✅ |
| D.3 | 横屏 Master-Detail | `frontend/lib/features/discovery/discovery_page.dart` | 左侧窄卡片流 + 右侧详情（内联于主页面） | ✅ |
| D.4 | 竖屏详情跳转 | `frontend/lib/features/discovery/discovery_detail_page.dart` | 列表点击后进入详情，底部悬浮操作条 | ✅ |
| D.5 | 单条 Promote/Ignore | `frontend/lib/features/discovery/providers/discovery_actions_provider.dart` | 对接 `PATCH /discovery/items/{id}`，支持乐观更新 | ✅ |
| D.6 | 详情页"查看原文"多来源适配 | `frontend/lib/features/discovery/discovery_detail_page.dart` | 单来源直接跳转；多来源时展开下拉菜单选择（HN 讨论页 / Reddit 帖 / 原始文章），参见设计文档(DISCOVERY_PATROL_INTEGRATION.md)§2.5 | ⏳ Phase 2 |

**完成标准**
- 满足设计文档 5.1 的核心交互：横屏双栏、竖屏单列、单条收藏/忽略、多来源原文跳转。

---

## Step E: 批量操作与筛选增强

| # | 子任务 | 涉及文件（新增/修改） | 说明 | 状态 |
|---|---|---|---|---|
| E.1 | 长按多选模式 | `frontend/lib/features/discovery/discovery_page.dart` | 复用 `collection` 的 selection UX | ✅ |
| E.2 | 批量 Promote/Ignore | `frontend/lib/features/discovery/widgets/discovery_batch_action_sheet.dart` | 对接 `POST /discovery/items/bulk-action` | ✅ |
| E.3 | 筛选栏组件 | `frontend/lib/features/discovery/widgets/discovery_filter_bar.dart` | 来源类型、分数范围、AI 标签、关键词 | ⏳ |
| E.4 | 分页与刷新 | `frontend/lib/features/discovery/providers/discovery_items_provider.dart` | 下拉刷新 + 滚动加载更多 | ✅ |

**完成标准**
- 能在大量发现条目下高效分拣，达到"探索流"可用状态。

---

## Step F: 设置中心扩展（对应设计 5.2）

| # | 子任务 | 涉及文件（新增/修改） | 说明 | 状态 |
|---|---|---|---|---|
| F.1 | AI 巡逻配置表单 | `frontend/lib/features/settings/presentation/tabs/automation_tab.dart` | 接入 `interest_profile`、`score_threshold`、`retention_days` | ✅ |
| F.2 | 来源管理面板 | `frontend/lib/features/settings/presentation/tabs/automation_tab.dart`, `frontend/lib/features/settings/presentation/widgets/discovery_source_dialog.dart` | CRUD + 手动同步（按 kind 分组） | ✅ |
| F.3 | Bot 迁移与修改合并包 | `frontend/lib/features/settings/presentation/tabs/push_tab.dart`, `frontend/lib/features/review/review_page.dart` | 将 Bot 配置能力从 Review 迁移至 Settings，支持双开关 | ✅ |

**完成标准**
- Discovery 相关配置全部集中在 Settings，可独立完成"画像/阈值/来源/监听开关"维护。

### Step F 补充：Bot 迁移与修改合并包（一次性完成）

**合并目标**
- 不再拆分"迁移"和"修改"两个子阶段；以单一交付包完成 Bot 配置迁移、模型改造、Review 清理和验收。

**合并包内容**
- Settings 承接配置：在 `push_tab.dart`（或其子组件）提供群组级 `is_monitoring` / `is_push_target` 双开关与保存动作。
- 数据层同步修改：`bot_chat.dart` 与 `bot_chats_provider.dart` 同步新增字段，`BotChatUpdate` 透传 PATCH 字段。
- Review 页面迁移清理：`TabController` 从 3 个 Tab 收敛为 2 个，移除 Bot 群组 Tab/FAB/配置入口。
- Review 遗留逻辑清理：删除 Bot 配置专用状态、方法、SSE 分支和无用 import，避免继续触发 Bot 配置请求。
- 导航替代：Review 中原配置入口统一替换为"前往设置"，跳转 `'/settings'`（必要时定位子页）。

**合并包验收**
- 进入 Review 页面不再看到 Bot 配置相关 UI（Tab、卡片、按钮、对话框）。
- Review 页面网络请求不再包含 `/bot/chats`、`/bot/status`、`/bot-config/service/telegram/*`。
- Bot 配置能力可在 Settings 页面完整完成且不回流到 Review。

---

## Step G: 主库详情多来源链接适配（source_links）

| # | 子任务 | 涉及文件（新增/修改） | 说明 | 状态 |
|---|---|---|---|---|
| G.1 | 新增 `source_links` 渲染组件 | `frontend/lib/features/collection/widgets/detail/components/source_links_section.dart` | 渲染来源列表、来源统计、原文入口 | ⏳ |
| G.2 | 接入详情信息卡 | `frontend/lib/features/collection/widgets/detail/components/content_side_info_card.dart` | 当 `contextData["source_links"]` 存在时显示来源区块 | ⏳ |
| G.3 | 原文按钮多来源分流 | `frontend/lib/features/collection/content_detail_page.dart` | 单来源直跳，多来源下拉菜单选择 | ⏳ |
| G.4 | 兼容旧 contextData | `frontend/lib/features/collection/widgets/renderers/context_card_renderer.dart` | 保留现有 question 渲染，叠加 source_links 逻辑 | ⏳ |

**完成标准**
- 被 promote 的 Discovery 内容在主库详情可看到来源组与多原文跳转。

---

## Step G2: Dashboard 发现概览（对接 Discovery Stats）

> 在现有仪表盘中增加发现流统计区块，对接 `GET /v1/discovery/stats`。

| # | 子任务 | 涉及文件（新增/修改） | 说明 | 状态 |
|---|---|---|---|---|
| G2.1 | 新增 Discovery Stats Provider | `frontend/lib/features/dashboard/providers/dashboard_provider.dart` | 新增 `discoveryStatsProvider`，对接 `/v1/discovery/stats` | ⏳ |
| G2.2 | 新增 Discovery Stats 模型 | `frontend/lib/features/dashboard/models/stats.dart` | 扩展或新增 `DiscoveryStats` 结构（各状态数量、来源分布、评分分布） | ⏳ |
| G2.3 | Dashboard 概览卡片 | `frontend/lib/features/dashboard/dashboard_page.dart` | 在"系统概览" `StatsGrid` 中追加发现流相关指标卡片：待分拣数、今日新增、平均分等 | ⏳ |
| G2.4 | 发现来源分布图 | `frontend/lib/features/dashboard/widgets/discovery_source_distribution_card.dart` | 展示各 `source_kind` 的内容数量分布（饼图/柱状图），点击可跳转到对应筛选的 Discovery 页 | ⏳ |
| G2.5 | 评分分布图 | `frontend/lib/features/dashboard/widgets/discovery_score_distribution_card.dart` | 展示 AI 评分区间分布（直方图），直观反映发现流质量 | ⏳ |

**完成标准**
- Dashboard 中可一目了然查看发现流的整体状态，点击指标卡可快速跳转到 Discovery 页面对应筛选视图。

---

## Step H: 测试、验收与文档

| # | 子任务 | 涉及文件（新增/修改） | 说明 | 状态 |
|---|---|---|---|---|
| H.1 | Provider 单测 | `frontend/test/features/discovery/providers/*_test.dart` | 覆盖列表分页、筛选参数、批量操作状态流转 | ⏳ |
| H.2 | 页面 Widget 测试 | `frontend/test/features/discovery/discovery_page_test.dart` | 覆盖横竖屏布局与多选交互 | ⏳ |
| H.3 | 设置页回归测试 | `frontend/test/features/settings/automation_tab_test.dart` | 覆盖配置项读写和来源 CRUD 流程 | ⏳ |
| H.4 | Bot 合并包回归测试 | `frontend/test/features/review/review_page_test.dart`, `frontend/test/features/settings/push_tab_test.dart` | 断言迁移后 Review 无 Bot 配置 UI/请求，且 Settings 可完成 Bot 配置 | ⏳ |
| H.5 | Dashboard 发现概览回归测试 | `frontend/test/features/dashboard/dashboard_page_test.dart` | 覆盖 Discovery Stats 卡片渲染与跳转 | ⏳ |
| H.6 | 文档更新 | `frontend/README.md`, `docs/architecture/DISCOVERY_STEPS.md` | 增加前端接入说明与状态同步 | ⏳ |

**完成标准**
- 功能链路可回归，且文档可指导后续维护。

---

## Step I（Phase 2）: 条件式聚合交互 (Conditional Aggregation)

> **目标**：实现重合内容的动态分组形态与拖拽交互。详细 UI 规范见 [DISCOVERY_EVENT_AGGREGATION.md](./DISCOVERY_EVENT_AGGREGATION.md)。

| # | 子任务 | 涉及文件（新增/修改） | 说明 | 状态 |
|---|---|---|---|---|
| I.1 | 动态树状模型 | `frontend/lib/features/discovery/models/discovery_models.dart` | `DiscoveryItem` 支持可选 `children` 与 `isGroup` 判定 | ⏳ |
| I.2 | 折叠分组组件 | `frontend/lib/features/discovery/widgets/discovery_group_card.dart` | 开发支持展开/收起的特殊渲染器 | ⏳ |
| I.3 | 拖拽管理交互 | `frontend/lib/features/discovery/discovery_page.dart` | 实现合并与拆分的 Drag & Drop 逻辑 | ⏳ |
| I.4 | 综述详情视图 | `frontend/lib/features/discovery/discovery_detail_page.dart` | 适配聚合组的综述与多方对比展示 | ⏳ |

**完成标准**
- 用户能通过拖拽自由管理事件分组，形态切换平滑。

---

## 3. 迭代切片

> 已与§1 实施顺序总览对齐，此处补充并行说明。

### Sprint 0（前后端协作）
- Step A — 接口契约对齐，不涉及前端 UI 编码，可与后端并行推进。

### Sprint 1（MVP 可用）
- Step B → Step C → Step D（线性依赖，不可并行）

### Sprint 2（效率化）
- Step E + Step F（可并行：筛选/批量操作与设置中心无交叉文件）

### Sprint 3（体验补全）
- Step G + Step G2 + Step H（G 与 G2 可并行：分属 collection 和 dashboard 模块）

### Phase 2（后续版本）
- Step I（依赖后端高级接口 + Enrichment Agent）

---

## 4. 风险与注意事项

- Discovery 设计文档中的部分接口尚未在后端完整实现，前端应先以 MVP 接口集落地。
- `BotChat` 双开关需要后端 schema 同步，否则设置页无法实现"监听/推送分离"。
- 导航栏新增 `Discovery` 后，需检查现有 `index` 依赖逻辑（尤其 `collection` 过滤器清理触发条件）。
- 批量操作建议统一走批量 API，避免逐条请求导致移动端性能和稳定性问题。
- Dashboard 的 Discovery Stats 依赖 `/v1/discovery/stats` 端点，需确认其返回结构包含各状态数量、来源分布和评分分布。
