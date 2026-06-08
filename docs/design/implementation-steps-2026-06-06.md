# VaultStream 待完成内容执行步骤总表

> 日期：2026-06-06  
> 目标：把 `docs/` 中提到的现有问题、需要改进之处、规划能力和规划新增内容收敛到一份单线执行台账，方便按顺序推进。  
> 排除项：RAG、embedding/语义索引策略、Agent 工具权限、Agent API bridge 策略、Agent 推荐与 Agent 工作流扩展。本表不安排这些内容；相关文档中的描述仅作为现有能力、历史背景或远期风险记录。

## 约束

1. 以可信自动化验证为主：后端单元/API 测试、前端 widget/unit 测试、静态分析、schema/OpenAPI gate、可复现脚本。
2. 不要求额外人工媒体材料或完整真实链路检查作为默认退出条件。
3. UI/动效类工作需要证明逻辑正确：组件存在真实目标、布局约束合理、状态转换可测试、路由参数可复现。
4. 涉及真实平台、真实账号、真实外部推送的功能，用自动测试覆盖本地逻辑，用冒烟脚本或手工检查作为补充证据；不把外部平台未登录、平台风控、网络不可用或外部服务不稳定当作默认阻塞。
5. 如果收藏同步、平台解析、发现源、推送目标等能力暂时因为未登录、缺 Cookie、缺真实账号或平台不可用而无法完整落地，应先保留后端 API 接口、DTO、状态模型和前端交互抽象，使界面功能、路由、结果页和错误提示可以继续实现并测试；真实平台接入作为后续补齐项。
6. Flutter/Dart 命令需要提权运行。
7. 后端测试必须使用仓库根目录 `.venv`，例如 `.venv\Scripts\python.exe -m pytest backend/tests -q`。
8. 实现时适当拆分 commit；commit 描述文本使用中文，且每个 commit 应能说明完成的功能边界和验证证据。
9. 不要为了同步状态而修改原始规划、审计、架构、API、数据库或适配器文档；完成某个 Step 或子项后，只在本文件对应 Step 的“实现情况”下追加状态、提交范围和验证结果，便于审核。
10. 本文件是执行台账；除非发现文档本身事实错误，否则不要把已完成状态分散写回其他 docs。

## Step 1：统一边界和基线

### 目标

先把执行范围、排除项和当前状态口径统一，防止后续按旧文档误做。

### 来源

- `docs/README.md`
- `docs/audits/2026-06-06-frontend-coordination-experience-audit.md`
- `docs/audits/2026-06-05-current-product-security-audit.md`
- `docs/architecture/ROADMAP_V2.md`
- `docs/validation/product-acceptance.md`

### 要做

1. 确认 README、审计、路线图、验收指南都指向本执行步骤。
2. 保持排除项一致：
   - RAG 问答。
   - embedding/语义索引自动策略。
   - semantic reindex 策略。
   - Agent 权限、Agent API bridge、Agent 推荐和 Agent 工作流。
3. 建立当前验证基线：
   - 后端非 integration 测试。
   - 后端 integration 失败分类。
   - Flutter analyze/test。
   - product smoke check。
   - OpenAPI/schema gates。
4. 将“历史文档结论”标为假设，实际状态以代码和当前测试为准。

### 约束

- 文档搜索不到把排除项列为当前实现任务的语句。
- 新版执行表覆盖非排除项的主要待办。
- `git diff` 能清楚显示只改了文档边界和执行计划。

### 实现情况

- 2026-06-06：已完成当前执行表边界核对。RAG、embedding/语义索引自动策略、semantic reindex 策略、Agent 权限、Agent API bridge、Agent 推荐和 Agent 工作流扩展只保留为排除项、历史背景或远期风险记录，本执行表不安排实现。
- 2026-06-06：后续实现状态只追加到本文件对应 Step 的“实现情况”下；不为同步状态而回写原始审计、路线图、架构、API、数据库或适配器文档。
- 2026-06-06：代码核对确认 Step 2 的关键问题在实现前仍存在：`frontend/lib/features/collection/content_detail_page.dart` 的 loaded 态 Hero target 是空白 full-page surface，因此后续以当前代码和测试为准，不采信旧文档中的完成结论。

## Step 2：收藏卡片到详情页转场

### 目标

修复收藏卡片进入详情页时落到空白整页 Hero 的问题。

### 来源

- `docs/known-issues/collection-card-detail-transition.md`
- `docs/audits/2026-06-06-frontend-coordination-experience-audit.md`
- `docs/architecture/ROADMAP_V2.md`

### 关键代码路径

- `frontend/lib/features/collection/widgets/list/collection_card_preview.dart`
- `frontend/lib/features/collection/widgets/list/content_card.dart`
- `frontend/lib/features/collection/content_detail_page.dart`
- `frontend/lib/routing/app_router.dart`

### 要做

1. 建立真实详情页首屏 `DetailHeroHeader`。
2. 用真实 header 替换 loaded 状态中的空白 `SizedBox.expand()` Hero target。
3. Header 包含 cover/fallback、title、author、platform、tags 和基础 surface。
4. 保持 loading preview 到 loaded header 的连续状态。
5. 覆盖文章、图集、视频、纯文本、无封面和返回路径。

### 约束

- Widget 测试或可复现组件测试证明 loaded 详情页 Hero child 不是空白 full-page surface。
- 路由测试证明 `GoRouter.extra` preview 能进入详情 loading 路径。
- `flutter analyze` 通过。

### 实现情况

- 2026-06-06：已建立 `DetailHeroHeader`，包含 cover/fallback、title、author、platform、tags 和稳定 surface，并复用现有 `NetworkThumbnail`、`buildImageHeaders`、`PlatformBadge`、`ContentParser.getDisplayImageUrl`。
- 2026-06-06：已用真实 `DetailHeroHeader` 替换 loaded 态中空白 `SizedBox.expand()` Hero target；loading 态仍保留 `CollectionCardPreview`，并继续使用同一 `collectionCardHeroTag` 和 `collectionCardFlightShuttleBuilder`。
- 2026-06-06：已更新 `frontend/test/widget/content_detail_transition_test.dart`，断言 loaded 态 `Hero.child` 是 `DetailHeroHeader`，并验证 title、author、tag 可渲染。
- 2026-06-06：验证已通过：提权运行 `cd frontend; dart format lib/features/collection/content_detail_page.dart test/widget/content_detail_transition_test.dart`、`cd frontend; flutter test test/widget/content_detail_transition_test.dart`、`cd frontend; flutter analyze`。

## Step 3：后台自动化策略层

### 目标

让用户可见开关约束后台自动行为，避免“关了设置但后台仍自动写回/同步/推送”。

### 来源

- `docs/audits/2026-06-06-frontend-coordination-experience-audit.md`
- `docs/audits/2026-06-05-current-product-security-audit.md`
- `docs/architecture/ROADMAP_V2.md`

### 关键代码路径

- `backend/app/services/post_ingest.py`
- `backend/app/tasks/discovery_sync.py`
- `backend/app/tasks/favorites_sync.py`
- `backend/app/tasks/distribution_worker.py`
- `backend/app/tasks/maintenance.py`
- `backend/app/tasks/parsing.py`
- `backend/app/services/patrol_service.py`
- `backend/app/services/distribution.py`
- `backend/app/services/config_service.py`
- `backend/app/schemas/discovery.py`

### 要做

1. 新增统一策略服务，例如 `AutomationPolicyService`。
2. 覆盖这些非排除策略：
   - `enable_auto_summary`
   - `enable_discovery_patrol` 或 `enable_ai_scoring`
   - `distribution_mode`
   - `enable_cookie_keepalive`
   - `ingest_mode`
   - `enable_favorites_sync_scheduler`
   - `allow_manual_favorites_sync_disabled_platform`
3. 后台入口显式声明 `trigger=auto/manual/retry`。
4. 发现巡逻评分受全局评分开关控制。
5. disabled 发现源手动同步默认拒绝，除非显式 `force=true`。
6. disabled 收藏平台单平台手动同步默认拒绝，除非显式覆盖。
7. `distribution_mode=paused` 时，规则刷新、解析完成、trigger-run 不产生外部推送。
8. Cookie 保活启动前检查策略。
9. 解析/导入入口根据 `ingest_mode` 决定只保存、解析或继续后处理。

### 约束

- 后端测试证明每个关闭策略都会阻断对应自动路径。
- API 测试覆盖 disabled 来源/平台的默认拒绝和 `force=true` 覆盖。
- 分发 worker 测试覆盖 paused 状态不领取或不推送。
- Cookie 保活测试覆盖关闭后不启动循环。

### 实现情况

- 2026-06-06：已新增 `backend/app/services/automation_policy.py`，集中提供收藏同步 scheduler、disabled 收藏平台手动同步、disabled 发现源手动同步、发现巡逻评分、分发入队/worker、Cookie keepalive 和 `ingest_mode` 的策略决策；默认值保持现有行为，只有显式关闭或 `distribution_mode=paused` 时阻断。
- 2026-06-06：已在 `backend/app/core/config.py` 增加策略配置落点：`distribution_mode`、`ingest_mode`、`enable_discovery_patrol`、`enable_ai_scoring`、`enable_cookie_keepalive`、`enable_favorites_sync_scheduler`、`allow_manual_favorites_sync_disabled_platform`。
- 2026-06-06：已接入策略入口：收藏同步 scheduler 关闭时跳过自动轮询；单平台收藏手动同步默认拒绝未启用平台，支持 `force=true` 覆盖；disabled 发现源手动同步默认拒绝，支持 `?force=true` 覆盖；`distribution_mode=paused` 阻断自动入队和 worker 领队列；Cookie keepalive 关闭后不启动循环；发现巡逻评分受策略开关控制。
- 2026-06-06：未扩展 RAG、embedding 自动策略或 Agent API bridge；`PostIngestService` 中既有 embedding 调用保持原状，未作为本 Step 新增能力推进。
- 2026-06-06：验证已通过：`.venv\Scripts\python.exe -m pytest backend\tests\test_automation_policy.py backend\tests\test_config_service.py backend\tests\test_tasks\test_favorites_sync_task.py backend\tests\test_tasks\test_distribution_task.py backend\tests\test_api\test_system.py backend\tests\test_api\test_discovery_sources.py -q`。结果 55 passed，存在既有 sqlite ResourceWarning。

## Step 4：媒体归档和解析成本控制

### 目标

补齐媒体归档、解析队列和批量导入的用户级控制，避免大批量导入时自动触发不可预估的平台请求、媒体处理和分发。

### 来源

- `docs/audits/2026-06-06-frontend-coordination-experience-audit.md`
- `docs/architecture/BACKEND.md`
- `docs/architecture/ROADMAP_V2.md`

### 关键代码路径

- `backend/app/services/config_service.py`
- `backend/app/tasks/parsing.py`
- `backend/app/services/content_service.py`
- `backend/app/tasks/discovery_sync.py`
- `frontend/lib/features/settings/presentation/tabs/system_tab.dart`
- `frontend/lib/features/collection/widgets/detail/components/post_processing_status_panel.dart`

### 要做

1. 把“媒体压缩处理”文案改为“自动归档远程媒体”。
2. 拆分图片压缩、图片数量、视频归档、视频数量/体积策略。
3. 处理状态中展示媒体归档是否启用和最近处理结果。
4. 增加 `ingest_mode` 的前端可见说明。
5. 动态页展示解析队列暂停/恢复状态和积压数。

### 约束

- 配置服务测试覆盖媒体归档字段。
- 解析任务测试覆盖不同媒体策略下是否处理图片/视频。
- 前端 widget 测试覆盖窄屏设置项展示。

### 实现情况

- 2026-06-06：已将媒体策略从单一“媒体压缩处理”扩展为“远程媒体归档”语义：`ArchiveMediaConfig` 增加 `images_enabled`、`videos_enabled`、`video_max_bytes`，并新增配置落点 `enable_archive_image_processing`、`enable_archive_video_processing`、`archive_video_max_count`、`archive_video_max_bytes`。
- 2026-06-06：解析任务已按图片/视频子策略分别执行归档：图片归档关闭时不调用 `store_archive_images_as_webp`；视频归档关闭时不调用 `store_archive_videos`；视频归档开启时传递 `max_videos` 和 `max_bytes`。发现源归档目前只处理图片，因此接入 `images_enabled`。
- 2026-06-06：处理状态接口新增 `archive_media` stage，输出远程媒体归档开关、图片/视频数量、已归档数量、图片数量上限、视频数量上限和视频字节上限，供详情页状态面板直接展示。
- 2026-06-06：前端系统设置页已改为“自动归档远程媒体”语义，增加图片归档、视频归档子开关，以及视频数量/字节上限输入；未修改原始审计/路线图文档。
- 2026-06-06：验证已通过：`.venv\Scripts\python.exe -m pytest backend\tests\test_config_service.py backend\tests\test_tasks\test_parsing_task.py backend\tests\test_tasks\test_discovery_tasks.py backend\tests\test_api\test_content_processing_status.py -q`（60 passed）；提权运行 `cd frontend; dart format lib/features/settings/presentation/tabs/system_tab.dart`、`cd frontend; flutter analyze`（No issues found）。

## Step 5：前端策略设置和能力状态

### 目标

把设置页从“模型字段配置”升级为“用户可理解能力 + 自动策略”。

### 来源

- `docs/audits/2026-06-06-frontend-coordination-experience-audit.md`
- `docs/audits/2026-06-05-current-product-security-audit.md`
- `docs/design/product-navigation-and-automation.md`

### 关键代码路径

- `frontend/lib/features/settings/presentation/tabs/automation_tab.dart`
- `frontend/lib/features/discovery/providers/discovery_settings_provider.dart`
- `frontend/lib/features/settings/providers/settings_provider.dart`
- `frontend/lib/features/review/widgets/automation_health_matrix_panel.dart`
- `frontend/lib/features/review/widgets/favorites_sync_automation_panel.dart`
- `frontend/lib/features/accounts/account_center_page.dart`

### 要做

1. “AI 发现”增加自动评分/巡逻开关。
2. 说明巡逻评分可能写入评分、原因、标签、摘要和可见状态。
3. 摘要开关文案改成“解析后自动生成内容理解/摘要”。
4. 收藏同步平台开关文案改为“自动同步此平台”。
5. disabled 来源/平台的手动同步入口显示拒绝或覆盖确认。
6. 分发页展示 `distribution_mode`。
7. 账号中心展示 Cookie 保活状态、最近执行、最近失败。
8. AI 能力状态保留内容理解、摘要、文本/视觉模型、巡逻评分等非排除能力。

### 约束

- 前端 widget 测试覆盖开关渲染、禁用态、覆盖确认。
- API mock 测试覆盖策略响应变化。
- `flutter analyze` 通过。

### 实现情况

- 2026-06-06：已在自动化设置页新增“自动化策略约束”区，展示并可切换 `enable_discovery_patrol`、`enable_ai_scoring`、`enable_auto_summary`、`distribution_mode`、`enable_cookie_keepalive`、`enable_favorites_sync_scheduler`、`allow_manual_favorites_sync_disabled_platform`；分发模式明确显示 `auto/paused`，摘要文案改为“解析后自动生成内容理解/摘要”。
- 2026-06-06：已补前端 API 抽象：发现源手动同步支持可选 `force` query，收藏同步触发支持可选 `force` payload；当前 UI 对禁用发现源和未启用收藏平台先显示策略拒绝提示，不默认绕过后端策略。
- 2026-06-06：已扩展 `/ai/capabilities` 的用户可见能力状态，新增 `text_llm`、`vision_llm`、`discovery_patrol`；前端能力摘要过滤掉本轮排除的 `semantic_search` 和 `agent`，不扩展 RAG、embedding 或 Agent 功能。
- 2026-06-06：已扩展 `/platform-health` 返回 `cookie_keepalive`，账号中心展示 Cookie 保活启用状态、最近运行和最近失败；该状态只依赖设置和后台任务记录，不要求平台已登录。
- 2026-06-06：验证已通过：`.venv\Scripts\python.exe -m pytest backend\tests\test_api\test_system.py::TestSystemAPI::test_platform_health_aggregates_auth_and_favorites_sync backend\tests\test_api\test_system.py::TestSystemAPI::test_ai_capabilities_report_user_facing_status -q`（2 passed）；提权运行 `cd frontend; dart format ...`、`cd frontend; flutter test test/widget/account_center_page_test.dart`、`cd frontend; flutter test test/widget/review_page_test.dart`、`cd frontend; flutter analyze`（No issues found）。

## Step 6：移动端复杂操作容器

### 目标

把复杂工作流从窄屏 dialog 中迁出，降低移动端布局风险。

### 来源

- `docs/audits/2026-06-06-frontend-coordination-experience-audit.md`
- `docs/architecture/ROADMAP_V2.md`

### 关键代码路径

- `frontend/lib/features/settings/presentation/widgets/setting_components.dart`
- `frontend/lib/features/collection/widgets/dialogs/filter_dialog.dart`
- `frontend/lib/features/review/widgets/distribution_rule_dialog.dart`
- `frontend/lib/features/settings/presentation/tabs/automation_tab.dart`
- `frontend/lib/features/accounts/account_center_page.dart`
- `frontend/lib/features/auth/presentation/widgets/interactive_login_dialog.dart`
- `frontend/lib/features/review/widgets/favorites_sync_automation_panel.dart`

### 要做

1. 新增 `AdaptiveTaskSurface`。
2. 新增或重构 `AdaptiveSettingsTile`。
3. 窄屏下 trailing 控件下移，Slider/Dropdown/输入框占满宽度。
4. 迁移：
   - 收藏同步预览和结果。
   - 发现源编辑。
   - 分发规则编辑。
   - 交互登录/二维码登录。
   - 收藏筛选器。
   - 内容详情后处理失败详情。

### 约束

- Widget 测试覆盖窄屏和宽屏布局分支。
- 组件约束测试证明主要表单控件不会被固定 padding 压到不可用。
- `flutter analyze` 通过。

### 实现情况

- 2026-06-06：已新增 `AdaptiveTaskSurface`，作为复杂任务弹层的统一响应式容器；窄屏使用 fullscreen dialog，宽屏使用受限宽度/高度的任务面板。
- 2026-06-06：已重构 `SettingTile` 的 trailing 布局：当容器宽度小于 560 且存在 trailing 控件时，开关、按钮、下拉等控件下移并占用独立行，避免窄屏固定横排挤压正文。
- 2026-06-06：已迁移发现源编辑 `_SourceEditDialog` 到 `AdaptiveTaskSurface`；添加/编辑发现源在窄屏下不再使用窄 dialog。
- 2026-06-06：已将 `DistributionRuleDialog` 改为响应式复杂表单容器：宽屏保留圆角 dialog，窄屏使用 fullscreen surface，表单滚动区和底部 actions 保持可用。
- 2026-06-06：验证已通过：提权运行 `cd frontend; dart format lib/features/settings/presentation/widgets/setting_components.dart lib/features/review/widgets/distribution_rule_dialog.dart lib/features/settings/presentation/tabs/automation_tab.dart test/widget/distribution_rule_dialog_test.dart`、`cd frontend; flutter test test/widget/distribution_rule_dialog_test.dart`（3 passed）、`cd frontend; flutter analyze`（No issues found）、`cd frontend; flutter test test/widget/account_center_page_test.dart`（1 passed）、`cd frontend; flutter test test/widget/review_page_test.dart`（6 passed）。

## Step 7：任务结果页和后台诊断

### 目标

把任务运行结果、失败原因、重试入口和相关对象做成可路由、可复查的结果页，而不是嵌套弹窗。

### 来源

- `docs/audits/2026-06-06-frontend-coordination-experience-audit.md`
- `docs/audits/2026-06-05-current-product-security-audit.md`
- `docs/design/product-navigation-and-automation.md`
- `docs/architecture/ROADMAP_V2.md`
- `docs/API.md`

### 关键代码路径

- `frontend/lib/routing/app_router.dart`
- `frontend/lib/features/dashboard/widgets/activity_timeline_card.dart`
- `frontend/lib/features/dashboard/widgets/background_diagnostics_card.dart`
- `frontend/lib/features/review/widgets/favorites_sync_automation_panel.dart`
- `frontend/lib/features/review/widgets/automation_health_matrix_panel.dart`
- `backend/app/services/background_task_state.py`

### 要做

1. 新增通用任务结果路由。
2. 收藏同步 run、发现源同步 run、平台解析测试、推送目标测试、推送目标真实发送测试都能进入结果页。
3. 结果页展示状态、触发来源、关联平台/来源/内容、错误原因、下一步动作。
4. 收藏同步完整失败列表和单条/批量重试迁移到结果页。
5. 后台任务诊断页展示 last run、last error、retry count、manual retry、recent failure payload。
6. 动态页从统计页结构继续演化为事件流和失败恢复入口。

### 约束

- 路由测试覆盖 run id 深链接和刷新读取。
- API 测试覆盖 run metadata/result/failure payload。
- 前端 widget 测试覆盖错误、成功、运行中三种状态。

### 实现情况

- 2026-06-06：已新增通用任务运行查询 API：`GET /api/v1/background-tasks/runs/{run_id}`，从已有 background task recent run 记录中按 run id 查找，返回 `task/status/started_at/finished_at/error/result` 以及 task-specific metadata；未新增数据库表或迁移。
- 2026-06-06：已将后台诊断 recent runs 的任务名范围收敛到 `_BACKGROUND_RUN_TASK_NAMES`，并纳入 Cookie keepalive run；`/background-tasks/diagnostics` 和单 run 查询使用同一任务名边界。
- 2026-06-06：已新增前端 `TaskResultPage` 和 `/tasks/:runId` 路由，通过 `backgroundTaskRunProvider(runId)` 刷新读取后端单 run API；页面展示状态、触发来源、关联平台、关联对象、错误原因、metadata 和 result。
- 2026-06-06：已将 `BackgroundDiagnosticsCard` 的 recent run 点击从嵌套弹窗改为跳转 `/tasks/{runId}`；旧弹窗代码已移除。
- 2026-06-06：验证已通过：`.venv\Scripts\python.exe -m pytest backend\tests\test_api\test_system.py::TestSystemAPI::test_background_task_run_lookup_by_id -q`（1 passed）；提权运行 `cd frontend; dart format ...`、`cd frontend; flutter test test/widget/task_result_page_test.dart`（3 passed）、`cd frontend; flutter test test/widget/dashboard_page_test.dart`（4 passed）、`cd frontend; flutter analyze`（No issues found）。

## Step 8：收藏同步产品化

### 目标

把收藏同步从后台开关升级为用户能控制范围、策略、失败恢复的产品流程。

### 来源

- `docs/design/product-navigation-and-automation.md`
- `docs/audits/2026-06-05-current-product-security-audit.md`
- `docs/audits/2026-06-06-frontend-coordination-experience-audit.md`
- `docs/API.md`

### 关键代码路径

- `backend/app/tasks/favorites_sync.py`
- `backend/app/routers/system.py`
- `backend/app/services/config_service.py`
- `frontend/lib/features/review/widgets/favorites_sync_automation_panel.dart`
- `frontend/lib/features/accounts/account_center_page.dart`
- `frontend/lib/features/discovery/discovery_page.dart`

### 要做

1. 增加收藏夹/分组范围选择。
2. 增加首次同步策略。
3. 增加远端取消收藏后的本地处理策略。
4. 增加冲突策略配置。
5. 支持同步进度、暂停、取消。
6. 完整失败列表页。
7. 失败项独立结果页。
8. 单条和批量失败候选重试保留 run 记录。
9. 同步候选进入收件箱处理流。
10. 自动化页继续保留同步间隔、单轮上限、重复内容策略等常用配置。

### 约束

- 后端测试覆盖范围策略、首次同步策略、取消收藏策略、重复策略。
- API 测试覆盖失败项单条/批量重试。
- 前端测试覆盖预览、结果、失败列表、策略展示。

### 实现情况

- 2026-06-06：代码核对确认已有能力包括：收藏同步预览、不推进 cursor 的 preview、单平台/全平台触发、run 记录、run 级 retry、失败项单条 retry、失败项批量 retry、重复内容策略、同步间隔、单轮上限和平台启用范围。
- 2026-06-06：已新增收藏同步产品策略配置落点：`favorites_sync_scope_strategy`、`favorites_sync_first_sync_strategy`、`favorites_sync_unfavorite_strategy`，并扩展 `FavoritesSyncConfig` 与 `/favorites-sync/status.policies`。默认值保持现有行为：全部收藏、首次只拉当前页、远端取消收藏后保留本地。
- 2026-06-06：已在策略值中保留平台收藏夹/分组、全量回填、远端取消收藏后本地归档的 placeholder 选项；这些选项作为 API/UI 抽象存在，不要求当前平台登录或平台 adapter 已支持真实分组/差异检测。
- 2026-06-06：已在收藏同步策略卡增加“同步范围”“首次同步”“取消收藏”三个可配置下拉，并保留同步间隔、单轮上限、重复处理等既有配置；失败项单条/批量重试 toast 的查看入口改为 `/tasks/{runId}`，复用 Step 7 任务结果页。
- 2026-06-06：验证已通过：`.venv\Scripts\python.exe -m pytest backend\tests\test_config_service.py::test_get_favorites_sync_config_filters_and_normalizes_values backend\tests\test_config_service.py::test_get_favorites_sync_config_accepts_product_policy_values backend\tests\test_api\test_system.py::TestSystemAPI::test_favorites_sync_trigger_returns_run_id_and_status_lists_recent_runs -q`（3 passed）；提权运行 `cd frontend; dart format ...`、`cd frontend; flutter test test/widget/review_page_test.dart`（6 passed）、`cd frontend; flutter analyze`（No issues found）。

## Step 9：账号中心和平台健康矩阵

### 目标

把登录、Cookie、收藏同步、发现同步、解析失败、推送目标健康统一到账号中心/自动化健康矩阵中。

### 来源

- `docs/design/product-navigation-and-automation.md`
- `docs/audits/2026-06-05-current-product-security-audit.md`
- `docs/audits/2026-06-06-frontend-coordination-experience-audit.md`

### 关键代码路径

- `frontend/lib/features/accounts/account_center_page.dart`
- `frontend/lib/features/review/widgets/automation_health_matrix_panel.dart`
- `frontend/lib/features/settings/presentation/tabs/connection_tab.dart`
- `backend/app/tasks/maintenance.py`
- `backend/app/services/config_service.py`

### 要做

1. 平台账号卡展示登录状态、Cookie 状态、最近验证、最近同步、最近失败。
2. 聚合发现源、解析失败、推送目标健康。
3. 平台能力测试矩阵覆盖不同平台和目标类型差异。
4. 行级异常跳转到任务结果页。
5. Cookie 保活开关、平台级保活状态和最近执行结果进入账号中心。

### 约束

- Provider/API 测试覆盖健康矩阵数据。
- 前端 widget 测试覆盖异常、正常、未配置状态。
- 后端测试覆盖 Cookie 保活策略和最近失败记录。

### 实现情况

- 2026-06-06：代码核对确认账号中心已展示平台登录 Cookie、登录检测、收藏同步开关状态、Cookie 保活开关状态、最近保活 run 和最近保活失败；健康矩阵已聚合平台账号、发现源和推送目标，并提供平台解析测试、发现源质量测试、发现源同步、推送目标刷新/连接测试/发送测试等行级操作。
- 2026-06-06：已将账号中心的 Cookie 最近运行/失败、最近收藏同步 run，以及自动化健康矩阵中平台收藏 run、发现源 run、推送目标 run、解析测试 run 的查看入口统一跳转到 `/tasks/{runId}`，复用 Step 7 的任务结果页；run id 使用路径编码，避免特殊字符破坏路由。
- 2026-06-06：未新增真实平台登录依赖；发现源、收藏同步、推送目标等仍通过既有 API/DTO/状态模型抽象承载，平台未登录或外部服务不可用时不阻塞 UI、路由和错误提示实现。
- 2026-06-06：验证已通过：提权运行 `cd frontend; dart format lib/features/accounts/account_center_page.dart lib/features/review/widgets/automation_health_matrix_panel.dart`、`cd frontend; flutter test test/widget/account_center_page_test.dart`（1 passed）、`cd frontend; flutter test test/widget/review_page_test.dart`（6 passed）、`cd frontend; flutter analyze`（No issues found）。

## Step 10：收件箱产品化

### 目标

把“发现内容”扩展为所有待决策候选的收件箱。

### 来源

- `docs/design/product-navigation-and-automation.md`
- `docs/audits/2026-06-06-frontend-coordination-experience-audit.md`
- `docs/audits/2026-06-05-current-product-security-audit.md`

### 关键代码路径

- `frontend/lib/features/discovery/`
- `backend/app/routers/discovery.py`
- `backend/app/tasks/discovery_sync.py`
- `backend/app/services/patrol_service.py`
- `frontend/lib/features/dashboard/dashboard_page.dart`

### 要做

1. 收件箱承接 RSS/Telegram 发现内容。
2. 收藏同步候选进入收件箱。
3. 解析失败待修复内容进入收件箱。
4. 低置信度或待人工确认内容进入收件箱。
5. 增加候选保留与清理策略文案。
6. 增加 `discovery_cleanup_mode`: `hard_delete / expire_only / archive`。
7. 修改 retention days 时说明只对新候选生效，或提供应用到现有候选的显式操作。
8. 收件箱动作保留收藏、忽略、稍后处理、加入规则、分发、修复失败、批量处理。

### 约束

- 后端测试覆盖清理策略和 retention 作用范围。
- 前端测试覆盖候选类型、批量动作和状态切换。
- 动态页待处理摘要能读取收件箱候选数量。

### 实现情况

- 2026-06-06：代码核对确认 RSS 和 Telegram Channel 已通过既有 `DiscoverySourceKind`、`DiscoverySyncTask` 和 `/discovery/sources` 进入收件箱；本轮未新增真实平台依赖，也未扩展 RAG、embedding 或 Agent 功能。
- 2026-06-06：已扩展收件箱候选模型：`DiscoveryItem` 列表/详情响应带出 `status`，前端根据 `status/source_type/ai_score` 推导候选类型，覆盖 RSS/Telegram、`favorites_sync` 收藏候选、解析失败待修复、低置信度和待人工确认；收件箱卡片显示候选类型与生命周期状态。
- 2026-06-06：已新增 `discovery_cleanup_mode` 配置落点，支持 `hard_delete / expire_only / archive`；默认保持既有 hard delete 行为。`expire_only` 只标记过期不删除，`archive` 使用既有 `deleted_at/context_data` 软归档隐藏，不新增表结构。
- 2026-06-06：发现保留天数设置文案已明确“修改后只影响新候选”；`/discovery/settings` 返回 `retention_scope=new_candidates_only`，更新 retention days 时写入说明，不自动改写既有候选。
- 2026-06-06：已补收件箱动作抽象：收藏、忽略仍实际改变 `discovery_state`；稍后处理、加入规则候选、请求分发、修复失败先写入 `context_data.inbox_action` 作为可测试 API/UI 抽象，不要求真实分发规则或平台修复链路当前可用。单条桌面/移动详情入口和批量动作面板均已暴露这些动作。
- 2026-06-06：动态页待处理摘要已从收件箱 stats 读取候选数量，并合并 `ingested/scored/visible` 作为待处理收件箱数，忽略/过期等非待处理状态不计入。
- 2026-06-06：验证已通过：`.venv\Scripts\python.exe -m pytest backend\tests\test_api\test_discovery_api.py backend\tests\test_tasks\test_discovery_tasks.py -q`（33 passed）；提权运行 `cd frontend; dart run build_runner build --delete-conflicting-outputs`、`cd frontend; dart format ...`、`cd frontend; flutter test test/unit/discovery_actions_provider_test.dart`（2 passed）、`cd frontend; flutter test test/widget/discovery_inbox_test.dart`（2 passed）、`cd frontend; flutter test test/widget/dashboard_page_test.dart`（5 passed）、`cd frontend; flutter analyze`（No issues found）。`build_runner` 输出 analyzer 语言版本提示但生成成功。
- 2026-06-06：前十步当前状态回归验证已通过：`.venv\Scripts\python.exe -m pytest backend\tests\test_automation_policy.py backend\tests\test_config_service.py backend\tests\test_tasks\test_favorites_sync_task.py backend\tests\test_tasks\test_distribution_task.py backend\tests\test_api\test_system.py backend\tests\test_api\test_discovery_sources.py backend\tests\test_tasks\test_parsing_task.py backend\tests\test_tasks\test_discovery_tasks.py backend\tests\test_api\test_content_processing_status.py backend\tests\test_api\test_discovery_api.py -q`（130 passed，存在既有 sqlite ResourceWarning）；提权运行 `cd frontend; flutter test test/widget/content_detail_transition_test.dart test/widget/distribution_rule_dialog_test.dart test/widget/account_center_page_test.dart test/widget/review_page_test.dart test/widget/task_result_page_test.dart test/widget/dashboard_page_test.dart test/widget/discovery_inbox_test.dart test/unit/discovery_actions_provider_test.dart`（24 passed）。

## Step 11：分发系统和外部副作用控制

### 目标

让分发规则、队列 worker、目标测试和历史回填都可预估、可暂停、可恢复。

### 来源

- `docs/audits/2026-06-06-frontend-coordination-experience-audit.md`
- `docs/audits/2026-06-05-current-product-security-audit.md`
- `docs/architecture/ROADMAP_V2.md`
- `docs/API.md`

### 关键代码路径

- `backend/app/services/distribution.py`
- `backend/app/tasks/distribution_worker.py`
- `backend/app/routers/distribution.py`
- `backend/app/routers/distribution_queue.py`
- `frontend/lib/features/review/`

### 要做

1. `DistributionService` 保持唯一业务入口。
2. 旧 engine/scheduler 包装逻辑逐步变成 thin wrapper 并在 breaking cleanup 中移除。
3. 分发规则保存前预估影响既有内容数量、会新增队列项数量、是否会自动推送。
4. 规则更新支持 `refresh_existing=false` 或 dry-run preview。
5. 新增目标时提供历史内容补建队列选项。
6. 分发队列失败详情和 retry history 进入结果页。
7. 队列项维度操作与内容维度操作继续保持明确边界。

### 约束

- 后端测试覆盖 dry-run、refresh_existing、paused mode、队列项维度操作。
- API 测试覆盖失败详情和 retry history。
- 前端测试覆盖规则保存预估和确认文案。

### 实现情况

- 未开始。

## Step 12：动态页、统计拆解和信息架构收口

### 目标

把“动态”做成运行和待办入口，把统计拆到上下文中，统一新旧文案。

### 来源

- `docs/design/product-navigation-and-automation.md`
- `docs/audits/2026-06-06-frontend-coordination-experience-audit.md`
- `docs/audits/2026-06-05-current-product-security-audit.md`

### 关键代码路径

- `frontend/lib/layout/app_shell.dart`
- `frontend/lib/routing/app_router.dart`
- `frontend/lib/features/dashboard/`
- `frontend/lib/features/discovery/`
- `frontend/lib/features/collection/widgets/dialogs/filter_dialog.dart`
- `frontend/lib/core/layout/responsive_layout.dart`

### 要做

1. 动态页继续演化为事件流。
2. 展示来源事件、同步事件、解析事件、分发事件、失败事件。
3. 把统计内容拆到：
   - 动态页：今日新增、失败任务、待审核、最近推送。
   - 收藏库：内容数量、平台分布、标签分布。
   - 自动化：同步成功率、推送成功率、失败趋势。
   - 收件箱：来源质量、AI 评分分布、忽略率。
4. 全局扫描用户可见“探索/发现/审核/推送”文案。
5. 保留“发现源”作为自动化输入源类型。
6. 页面级概念使用动态、收藏库、收件箱、自动化、候选。
7. 手机收藏库默认单列，或提供密度切换。
8. 内容详情移动端 action 改成主按钮 + overflow。

### 约束

- 前端测试覆盖旧路由 redirect 和主导航入口。
- 文案扫描不再出现错误的页面级旧概念。
- Widget 测试覆盖收藏库密度和详情 action overflow。

### 实现情况

- 未开始。

## Step 13：架构收敛和工程质量

### 目标

清理当前架构漂移，提升后续变更可测试性和可维护性。

### 来源

- `docs/architecture/ROADMAP_V2.md`
- `docs/architecture/BACKEND.md`
- `docs/audits/2026-06-05-current-product-security-audit.md`

### 关键代码路径

- `backend/app/services/config_service.py`
- `backend/app/tasks/parsing.py`
- `backend/app/services/distribution.py`
- `backend/app/services/background_task_state.py`
- `backend/app/core/event_bus.py`
- `frontend/lib/features/`
- `frontend/lib/core/`

### 要做

1. 继续迁移高价值调用方到 typed `ConfigService`。
2. 保留 OpenAPI 和 schema gate 为端点/迁移必跑检查。
3. `ContentParser` 按职责拆分：
   - 任务编排。
   - adapter parsing。
   - archive media processing。
   - post-ingest scheduling。
   - error/dead-letter handling。
4. 高价值动态契约转为 typed DTO。
5. EventBus process-local 风险继续通过公开 snapshot 和诊断暴露。
6. 大型 Stateful widget 按状态所有权拆分。
7. Discovery detail 后续布局工作聚焦降低桌面手工布局复杂度。
8. 增加 backup/restore 文档，覆盖 SQLite data、media storage、config secrets。
9. 新增服务端 URL 获取入口必须复用 `safe_fetch`。
10. 监控非 integration 测试中的 `ResourceWarning` 噪音，按可复现失败处理。
11. 扩展前端测试覆盖，优先覆盖策略、路由、结果页和复杂表单。

### 约束

- 每个重构步骤都有对应单元测试或 contract test。
- OpenAPI/schema gate 通过。
- 后端非 integration 测试通过。
- Flutter analyze/test 通过。

### 实现情况

- 未开始。

## Step 14：平台适配和来源扩展

### 目标

把平台适配器文档中的待扩展项纳入低优先级产品 backlog，避免散落在 adapter 文档中。

### 来源

- `docs/adapters/*.md`
- `docs/audits/2026-06-05-current-product-security-audit.md`

### 要做

1. 新增发现来源时必须端到端补齐 scraper、API 和 UI。
2. Bilibili：评估 Audio 类型完整支持。
3. Weibo：评估“超话”和“微栏目”等特殊内容识别。
4. Zhihu：如确有需求，再评估完整评论列表，注意数据量和额外 API 成本。
5. 平台能力测试矩阵补齐各平台边界。
6. 所有服务端 URL 抓取继续复用 SSRF 防护路径。

### 约束

- 每个平台新增能力都要有 adapter 单元测试和 API 测试。
- 对真实平台依赖只作为可选冒烟，不作为默认自动验收阻塞。

### 实现情况

- 未开始。

## Step 15：文档和验收体系收口

### 目标

让文档表达和当前执行计划一致，避免旧计划重新污染任务拆分。

### 来源

- `docs/README.md`
- `docs/validation/product-acceptance.md`
- `docs/archive/`
- 所有当前文档

### 要做

1. README 保持当前必读顺序。
2. 旧审计、旧计划、旧修复记录进入 archive 或明确标注为历史。
3. 产品验收指南降级为分层验收：
   - 自动测试。
   - 冒烟脚本。
   - 可选真实平台检查。
4. 当前执行表保持为非排除项总台账。
5. 每完成一个 Step，更新本表状态和相关文档链接。

### 约束

- 文档搜索能确认排除项没有进入当前执行项。
- 本执行表覆盖 docs 中非排除的主要待办。
- 文档不要求 agent 默认执行额外人工媒体材料或完整真实链路检查。

### 实现情况

- 未开始。

## 最终执行顺序

1. 统一边界和基线。
2. 收藏卡片到详情页转场。
3. 后台自动化策略层。
4. 媒体归档和解析成本控制。
5. 前端策略设置和能力状态。
6. 移动端复杂操作容器。
7. 任务结果页和后台诊断。
8. 收藏同步产品化。
9. 账号中心和平台健康矩阵。
10. 收件箱产品化。
11. 分发系统和外部副作用控制。
12. 动态页、统计拆解和信息架构收口。
13. 架构收敛和工程质量。
14. 平台适配和来源扩展。
15. 文档和验收体系收口。

## 排除项

这些内容不进入本执行序列：

- 自动语义索引总开关。
- embedding 成本/隐私策略。
- semantic reindex 显式覆盖语义。
- 向量索引后端切换或 sqlite-vec 试点。
- RAG 问答模式。
- 语义/RAG 新能力扩展。
- Agent 工具权限。
- Agent API bridge 策略。
- Agent 推荐进入收件箱。
- Agent 工作流、命令面板或渲染模型扩展。
