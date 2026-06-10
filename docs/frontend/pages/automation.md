# 自动化页面

## 文档状态

active

## 当前代码

- 页面：`frontend/lib/features/review/review_page.dart`
- 路由：`/automation`、`/review`
- 主要组件：分发队列、规则配置、收藏同步面板、自动化健康矩阵。

## 当前界面内容

- 页面整体是 `Scaffold` + 毛玻璃 `FrostedAppBar`，标题为“自动化”。AppBar 下方是 4 个 tab：分发队列、收藏同步、健康矩阵、推送历史；`TabBarView` 承载四个工作区。路由可通过初始 tab 参数直接打开队列、收藏同步、健康或历史视图。页面监听队列更新和推送相关 SSE 事件，收到事件后刷新对应 provider，并用 `SnackBar` 提示用户。

### 分发队列 tab

- 该 tab 同时展示分发规则和待处理内容队列。布局在 900px 左右切换：宽屏使用左右分栏 `Row`，左侧固定约 360px 的规则侧栏，右侧 `Expanded` 显示队列；窄屏使用纵向 `Column`，顶部是规则选择器，下面是队列区域。
- 规则侧栏包含标题、新建规则按钮、规则搜索框、一个“全部内容”入口，以及按规则渲染的 `RuleListTile` 列表。选中规则后展示 `RuleConfigPanel`，内容包括包含/排除标签、标签匹配模式、NSFW 策略、频率限制、人工审批开关、推送目标 chips，以及编辑/删除操作。
- 窄屏规则选择器使用 `DropdownMenu` 选择规则，并用 `AnimatedSize` 展开/收起当前规则配置摘要，避免在手机宽度下占据过多垂直空间。
- 队列主体顶部是状态筛选 `SegmentedButton`，按待推送、已过滤、已推送展示实时计数；外层可横向滚动，避免窄屏溢出。
- 待推送队列使用可拖拽排序的 `ReorderableListView`，拖拽代理带阴影和动画；已过滤/已推送列表使用普通 `ListView.separated`。队列卡片包含时间/计划区、封面缩略图、标题、平台与标签、状态信息和右侧操作按钮。时间区弹出菜单支持立即推送、延后 10 分钟、延后 30 分钟、延后 1 小时和自定义时间。
- 队列支持多选模式，选中后显示批量操作栏，用于批量推送、重新排队、过滤或其他队列动作。

### 收藏同步 tab

- 主体是 `RefreshIndicator` 包裹的纵向 `ListView`，按卡片组织收藏同步工作流。
- 顶部总览卡显示当前运行状态、已启用平台数、认证可用平台数、失败任务数、单轮拉取上限、同步间隔和最近同步时间等指标，指标通过 `Wrap` 自动换行。
- 命令栏使用 `Wrap` 排列“同步全部”“预览同步”“刷新状态”等按钮，窄屏下按钮会自动换行。
- 策略卡展示同步范围、拉取策略、重复内容处理、首次同步策略、取消收藏策略、同步间隔、单次拉取上限等配置项，并提供跳转到设置页高级参数的入口。
- 平台状态区使用响应式网格：宽屏约三列，中等宽度两列，窄屏一列。每个平台卡片包含平台图标、认证状态、同步速率/限制、最近错误、预览按钮和同步按钮。
- 最近运行记录展示最近若干次收藏同步 run。每条 run 显示平台、状态、时间、统计摘要和失败信息；失败项提供重试入口，点击 run 可打开运行详情。

### 健康矩阵 tab

- 主体同样是 `RefreshIndicator` + `ListView`。顶部状态横幅汇总整体健康程度、问题数量，并提供跳转动态页的按钮。
- 下面按平台账号、发现源、推送目标分成三张健康 section。布局在约 980px 处切换：宽屏用 `Wrap` 多列排列，窄屏用 `Column` 单列堆叠。
- 每个健康 section 内部由 `_HealthRow` 组成：左侧图标和标题，中间副标题/问题摘要，右侧状态标签和操作按钮。平台账号行可查看最近同步结果、测试解析、检测登录；发现源行可检查质量或触发同步；推送目标行可测试连接、发送测试消息或刷新状态。

### 推送历史 tab

- 推送历史是 `RefreshIndicator` + `ListView.separated`。每条 `PushedRecordTile` 使用 `ListTile` 展示状态头像、平台与状态标签、目标 ID、消息 ID、错误信息、推送时间和失败重试按钮。
- 空态显示历史图标和“暂无推送记录”文案。

### 弹出界面与临时状态

- 新建/编辑规则会打开 `DistributionRuleDialog`。该对话框包含名称、描述、优先级、频率限制、时间窗口、NSFW 策略、人工审批、标签筛选、渲染配置、推送目标选择和回填模式；对话框在窄屏下切换为更紧凑的布局。
- 删除规则、规则回填、推送目标测试消息等高风险动作使用 `AlertDialog` 二次确认。
- 自定义队列时间使用系统 `showTimePicker`。
- 收藏同步预览和运行详情使用对话框展示。预览对话框显示预计拉取、新增、已存在、跳过等统计；运行详情对话框展示平台级结果、失败项列表和单条失败重试入口。
- 健康矩阵中的解析测试使用输入 URL 的 `AlertDialog`，测试结果通过 `SnackBar` 反馈。

## 承担职责

- 管理分发队列和推送规则。
- 查看自动化任务状态。
- 当前也承担收藏同步和平台健康诊断，但这是需要收敛的问题。

## 不承担职责

- 不应承担平台账号登录/解绑主流程。
- 不应承载所有系统设置。
- 不应重复实现任务详情弹窗。

## 与其他页面交互

- 动态页的收藏同步任务可跳转到本页收藏同步 tab。
- 分发队列操作影响收藏内容的推送状态。
- 健康矩阵会跳转账号中心或设置页。

## 后端/API 关联

- 读取接口：`GET /api/v1/distribution-queue/*`、`GET /api/v1/distribution-rules`、`GET /api/v1/favorites-sync/status`、`GET /api/v1/platform-health`。
- 写入接口：分发队列操作、规则操作、收藏同步触发和失败重试。
- 后台任务：分发 worker、收藏同步 run、后台诊断。

## 当前问题

- 自动化页职责过宽问题见 `../../issues/frontend-automation-page-responsibility-overload.md`。
- 账号能力重复问题见 `../../issues/frontend-account-entry-responsibility-duplication.md`。
- `/automation` 与 `ReviewPage` 命名不一致问题见 `../../issues/automation-review-doc-source-split.md`。
- 收藏同步 placeholder 策略暴露问题见 `../../issues/frontend-favorites-sync-placeholder-strategy-leak.md`。
- 前端控制面与后端自动化策略缺口见 `../../issues/frontend-control-policy-gaps.md`。

## 尚未实现 / 计划扩展

- 无本页单独计划；分发、收藏同步、诊断和账号能力的拆分边界以 `../../issues/frontend-automation-page-responsibility-overload.md` 为准。
