# 自动化页面

## 文档状态

active

## 当前代码

- 页面：`frontend/lib/features/automation/automation_page.dart`
- 路由：`/automation`
- 主要组件：自动化总览、收藏同步面板、分发队列/规则、推送历史、自动化健康矩阵。

## 当前界面内容

- 页面整体是 `Scaffold` + 毛玻璃 `FrostedAppBar`。默认标题为“自动化”；进入域内容后标题切换为“收藏同步”“分发”或“解析 / 后处理”，AppBar 左侧显示返回总览按钮。
- 页面不再使用顶层 `TabBar` / `TabBarView`。路由 query `tab=favorites|favorites-sync|sync` 会直接进入收藏同步域，`tab=queue|distribution|history|logs|pushed` 会进入分发域，`tab=health|matrix|processing|diagnostics` 会进入解析 / 后处理域；未带 tab 时进入自动化总览。
- 页面监听队列更新和推送相关 SSE 事件，收到事件后刷新分发队列、推送历史和统计 provider，并用 `SnackBar` 提示用户。

### 自动化总览

- 总览主体是 `RefreshIndicator` 包裹的纵向 `ListView`，内边距为 20px，底部留出 40px。
- 顶部是强调色圆角概览卡，展示“自动化总览”标题、说明文案，以及 `Wrap` 布局的指标块：待分发、已过滤、已推送、需处理。指标来自分发队列统计、收藏同步状态、推送历史和平台健康摘要。
- 概览卡下方是三张域入口卡：收藏同步、分发、解析 / 后处理。宽度大于约 900px 时三卡横向 `Row` 等宽排列；窄屏下使用纵向 `Column` 堆叠。每张卡展示标题、摘要、主指标、次指标和进入箭头。
- 如果存在同步失败、推送失败或平台/处理链路异常，底部显示“需要处理”面板。面板按问题类型列出可点击的 `ListTile`，分别进入分发历史、收藏同步或解析 / 后处理域。

### 收藏同步域

- 收藏同步域复用 `FavoritesSyncAutomationPanel`。主体是 `RefreshIndicator` + 纵向 `ListView`。
- 顶部总览卡显示运行状态、已启用平台数、认证可用平台数、失败任务数、单轮拉取上限、同步间隔和最近同步时间。
- 命令栏使用 `Wrap` 排列“同步全部”“预览同步”“刷新状态”等按钮。
- 策略卡展示同步范围、拉取策略、重复内容处理、首次同步策略、取消收藏策略、同步间隔、单次拉取上限等配置项，并提供跳转设置高级参数的入口。
- 平台状态区使用响应式网格；最近运行记录展示收藏同步 run，点击 run 仍会打开运行详情对话框。

### 分发域

- 分发域顶部使用 `SegmentedButton` 在“队列与规则”和“推送历史”之间切换。这是域内局部切换，不再作为自动化页顶层 tab。
- “队列与规则”视图保留原分发队列布局：宽屏使用左右分栏 `Row`，左侧固定约 360px 的规则侧栏，右侧 `Expanded` 显示队列；窄屏使用纵向 `Column`，顶部规则选择器，下面是队列区域。
- 规则侧栏包含标题、新建规则按钮、规则搜索框、“全部内容”入口和自定义规则列表。选中规则后展示 `RuleConfigPanel`，可编辑/删除/启停规则。
- 队列主体顶部是状态筛选 `SegmentedButton`，按待推送、已过滤、已推送展示实时计数；待推送队列使用 `ReorderableListView`，已过滤/已推送列表使用普通列表。队列仍支持多选和批量操作。
- “推送历史”视图展示 `PushedRecordTile` 列表，失败记录保留重试入口；空态显示“暂无推送记录”。

### 解析 / 后处理域

- 解析 / 后处理域当前复用 `AutomationHealthMatrixPanel`，作为平台账号、发现源、推送目标和后续处理链路的健康摘要入口。
- 主体是 `RefreshIndicator` + `ListView`。顶部状态横幅汇总整体健康程度和问题数量，并提供跳转动态页的按钮。
- 下方按平台账号、发现源、推送目标分成三张 health section。约 980px 以上宽度使用 `Wrap` 多列排列，窄屏使用 `Column` 单列堆叠。
- 每个 section 内部由健康行组成，展示图标、标题、副标题/问题摘要、状态标签和操作按钮。平台账号行可查看最近同步结果、测试解析、检测登录；发现源行可检查质量或触发同步；推送目标行可测试连接、发送测试消息或刷新状态。

### 弹出界面与临时状态

- 新建/编辑规则会打开 `DistributionRuleDialog`。该对话框包含名称、描述、优先级、频率限制、时间窗口、NSFW 策略、人工审批、标签筛选、渲染配置、推送目标选择和回填模式。
- 删除规则、规则回填、推送目标测试消息等高风险动作使用 `AlertDialog` 二次确认。
- 自定义队列时间使用系统 `showTimePicker`。
- 收藏同步预览和运行详情仍使用对话框展示。预览对话框显示预计拉取、新增、已存在、跳过等统计；运行详情对话框展示平台级结果、失败项列表和单条失败重试入口。
- 健康矩阵中的解析测试使用输入 URL 的 `AlertDialog`，测试结果通过 `SnackBar` 反馈。

## 承担职责

- 展示自动化总览和三大域入口：收藏同步、分发、解析 / 后处理。
- 管理分发队列和推送规则。
- 查看收藏同步、推送历史和自动化健康状态。

## 不承担职责

- 不应承担平台账号登录/解绑主流程。
- 不应承载所有系统设置。
- 不应长期重复实现任务详情弹窗。

## 与其他页面交互

- 动态页的收藏同步任务可跳转到本页收藏同步域。
- 分发队列操作影响收藏内容的推送状态。
- 解析 / 后处理域会跳转设置账号相关 tab 或其他设置区域；账号修复流程后续应收敛为“账号与平台”强子页入口。

## 后端/API 关联

- 读取接口：`GET /api/v1/distribution-queue/*`、`GET /api/v1/distribution-rules`、`GET /api/v1/favorites-sync/status`、`GET /api/v1/platform-health`。
- 写入接口：分发队列操作、规则操作、收藏同步触发和失败重试。
- 后台任务：分发 worker、收藏同步 run、后台诊断。

## 当前问题

- 自动化页职责过宽问题已进入三域化处理中，见 `../../issues/frontend-automation-page-responsibility-overload.md`。
- 旧账号中心重复入口已按 `resolved_by_removal` 归档，见 `../../issues/archive/frontend-account-entry-responsibility-duplication.md`。
- `/automation` 与旧 Review 命名不一致问题已按 `resolved_by_removal` 归档，见 `../../issues/archive/automation-review-doc-source-split.md`。
- 收藏同步 placeholder 策略暴露问题见 `../../issues/frontend-favorites-sync-placeholder-strategy-leak.md`。
- 前端控制面与后端自动化策略缺口见 `../../issues/frontend-control-policy-gaps.md`。

## 尚未实现 / 计划扩展

- 自动化三域化仍只是第一阶段：分发、收藏同步、解析 / 后处理仍复用旧内容组件，尚未拆成独立 Section Shell / Detail Shell。
- 收藏同步 run 详情、推送历史失败处理和解析测试仍有弹窗形态，后续应逐步迁移到 `/tasks/:runId`、通知中心或对应域下钻页面。
