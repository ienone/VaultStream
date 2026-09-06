# 长程实现独立复审

## 状态

archived。2026-09-06 已完成本次 Review 范围的实现纠偏、架构精简、UI/UX 整改与本地验证。保留原始审查证据；以下处理表记录整改结果及验收边界。

2026-09-06 后续测试精简：用户批准删除低价值测试与用毕探针。本文保留当时的验收记录，部分测试和诊断脚本已删除；当前永久保障及最新执行结果见 [验证策略](../../backend/testing.md)。前后截图继续保留。

自动化首层去卡片、横竖屏补查与本轮交付见 [2026-09-07 层级与适配整改](2026-09-07-layout-and-delivery.md)。

## 导航与设置层级调整（2026-09-07）

根据用户提供的 Animeko 截图，读取了 [Animeko 自适应导航实现](https://github.com/open-ani/animeko/blob/main/app/shared/ui-adaptive/src/commonMain/kotlin/ui/adaptive/navigation/AniNavigationSuiteScaffold.kt)、[设置主从布局](https://github.com/open-ani/animeko/blob/main/app/shared/ui-settings/src/commonMain/kotlin/ui/settings/SettingsScreen.kt)，以及 [Mihon 主页导航](https://github.com/mihonapp/mihon/blob/main/app/src/main/java/eu/kanade/tachiyomi/ui/home/HomeScreen.kt)、[设置单双栏导航](https://github.com/mihonapp/mihon/blob/main/app/src/main/java/eu/kanade/tachiyomi/ui/setting/SettingsScreen.kt)。本次借鉴目的地与页面动作分开、设置列表与详情按空间切换的组织方式，沿用 Flutter、GoRouter 和既有组件实现。

- 设置宽屏删除中间竖线、正文内层圆角框、重复的分区标题和侧栏范围说明。右侧标题与正文共用一块连续表面，正文仍限宽；窄屏与短横屏使用列表进入详情。
- 删除桌面顶部“保存内容”长胶囊、扩展侧栏、侧栏工具队列，以及底栏右侧保存和省略号。主导航只有动态、收藏库、自动化；600 宽开始使用窄侧栏，短横屏只显示导航图标。
- 三个主页共用页头保存与工具动作；收藏页选择模式保持局部动作。保存仍进入既有统一捕获表面，工具菜单保留全局搜索、Agent、消息盒子、账号中心和设置，未读数来自现有消息事实。
- 收敛原来的移动/桌面 Shell 和四组保存/工具组件，不增加依赖、配置层或另一套路由框架。系统分享、三个主分支的状态和全局播放器保留。
- 修复分区切换清空来源路由的问题：只替换当前设置地址。窄屏返回先回分区列表，再回进入设置前的页面。

验证：最终 `flutter analyze --no-pub` 无问题，现有 `flutter test --no-pub` 6 项通过；JS Web 构建可运行。四尺寸 390×844、844×390、768×1024、1200×900 的 8 项临时交互检查通过后删除，覆盖导航目的地、切换与缩放保留输入、工具入口、设置单双栏和来源返回。临时测试使用实际 Shell、GoRouter 与设置页面，主分支输入页和配置读取替换在测试边界，不把它描述成所有业务链路验收。

Chrome 使用实验库的专用只读 API、不启动 worker。实际检查四尺寸设置及导航，打开工具菜单与保存表面；收藏关键词在切换主分支后保留，自动化进入设置并切换分区后能返回自动化。另检查 320 宽收藏页头。截图过程中重新启动过专用只读服务，完成后收藏数据可重新加载；这不证明原生端或长期连接的稳定性。没有提交保存、修改配置或触发平台同步/外部发送；系统软键盘、原生后台播放与辅助技术仍未实机验收。

| 对照 | 此前 | 本次 |
| --- | --- | --- |
| 桌面设置：去掉重复分隔与内层容器 | ![此前桌面设置](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-06-implementation-review/after/sources-1200.png) | ![本次桌面设置](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-navigation-settings/settings-1200.png) |
| 桌面导航：移除长胶囊与工具队列 | ![此前桌面导航](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-ui-cleanup/automation-1200.png) | ![本次桌面导航](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-navigation-settings/automation-1200.png) |
| 手机导航：底栏只保留三个目的地 | ![此前手机导航](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-ui-cleanup/automation-390.png) | ![本次手机导航](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-navigation-settings/automation-390.png) |

| 尺寸补查 | 设置 | 主导航 |
| --- | --- | --- |
| 手机 | ![手机设置](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-navigation-settings/settings-390.png) | ![最窄收藏页头](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-navigation-settings/collection-320.png) |
| 横屏 | ![横屏设置](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-navigation-settings/settings-844.png) | ![横屏导航](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-navigation-settings/automation-844.png) |
| 平板 | ![平板设置](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-navigation-settings/settings-768.png) | ![平板导航](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-navigation-settings/automation-768.png) |

![页头工具菜单](/Users/ienone/coding/vaultstream/docs/issues/assets/2026-09-07-navigation-settings/tools-1200.png)

## UI 代码复核收尾（2026-09-07）

本次复核确认此前 U8 的“删除空封面/空简介”未覆盖所有模板，以下结果补充并修正旧记录；不能仅依据旧表中的“完成”认定当前实现。

| 代码复核项 | 本次处理 |
| --- | --- |
| 未接线的规则搜索 | 删除假搜索框、空规则重复新建按钮、全部内容装饰底座与重复说明；同时修复全部内容无法清除规则筛选。 |
| Agent 工具重复记录 | 按已有 `tool_call_id` 原位合并调用与结果，保留参数与引用，重复结果不增加卡片，延迟调用不回退完成态；忽略未知事件原始 JSON，移除流失败的重复提示和内部错误码前缀。 |
| 队列空态 | 删除星形大图与休息文案，按三种筛选分别表达空状态，保留刷新。推送历史空态也去掉装饰大图。 |
| 总览伪零计数 | 删除指标装饰 Chip/图标底座；加载、失败、真实计数分别呈现；同步明确为调度状态。分发统计缺少必需字段不再默认为 0。 |
| 可选媒体占位 | 无封面、无笔记配图、无媒体说明不制造占位；保留主要媒体缺失状态，来源播放动作仅对 HTTP(S) 原文显示；删除未抓取原因猜测与重复 AI 来源解释。 |
| 主页重复身份 | 复用详情头与来源头像，删除第二套标题/头像及空简介标题和提示；实际简介、图片继续展示。 |
| 自适应表面及小残留 | 来源短表单按内容收缩，整表滚动，不强制全屏/固定高度；设置图标、说明可选，清除重复说明、重复图标和空 trailing 间距；连接测试不直出异常对象或装饰 emoji。 |

保留理由：来源清理策略有“硬删除、仅过期、归档”三种真实选择，继续保留；媒体归档阶段的状态与设置入口有独立职责，继续保留；工具参数/结果可展开，人工编辑保护、审批与持久任务边界均保留。

验证：真实 controller 与筛选 notifier、实际模板和共享表面完成 11 项临时验收；与现有 6 项回归合计 17 项通过。覆盖调用/结果交错与重复、参数与引用数据保留、失败结果、未知事件、筛选复位、总览加载/失败、四尺寸空态与表单、双倍字号与模拟键盘 inset。临时脚本验证后删除。最终 `flutter analyze --no-pub` 无问题，`git diff --check` 通过。Flutter Web JS 构建通过；Wasm 因现有 secure storage 依赖不支持，未验收。

真实 Chrome 使用实验库的只读接口、禁用 lifecycle worker：检查来源表单的 390×844、844×390、768×1024、1200×900，输入后切换尺寸仍保留名称与地址，横屏滚动至操作区，取消退出；总览读取真实非零数据。没有提交来源配置或触发同步。截图：![手机表单](../assets/2026-09-07-ui-cleanup/source-form-390.png)、![横屏表单](../assets/2026-09-07-ui-cleanup/source-form-844.png)、![平板表单](../assets/2026-09-07-ui-cleanup/source-form-768.png)、![桌面表单](../assets/2026-09-07-ui-cleanup/source-form-1200.png)、![桌面总览](../assets/2026-09-07-ui-cleanup/automation-1200.png)、![手机总览](../assets/2026-09-07-ui-cleanup/automation-390.png)。既有整改前截图仍在下文；本次没有重建旧版本或伪造同场景前图。

边界：工具生命周期使用真实状态转换与构造的协议事件，未调用真实模型；模板空态由实际 Widget 验证，未重新逐页人工验收所有详情模板；原生键盘、外部发送/同步及设备生命周期未验证。本节仅关闭本次代码复核问题，不将这些边界写为通过。

## 整改结果（2026-09-06）

R1–R8、A1–A5、U1–U12 均已处理；本次 Goal 完成。原始审查正文描述整改前状态，不能与下表混作当前结论。完成范围不包含下文明确列出的真实外部服务与原生设备验收。

| 项目 | 当前处理与证据 |
| --- | --- |
| R1 | 拒绝路径点段、编码/重复分隔符及内嵌 query；真实 HTTPX/ASGI 回归确认禁用路由不可达，合法 query 保持。 |
| R2 | pending 条件更新领取；副作用前提交 approved / running。批准、拒绝、取消共用数据库排他转换；独立 session 缓存 pending 的交错批准/拒绝只执行一次。 |
| R3 | 空来源仍保留资产身份；快照读回后重新请求 playback manifest，初始化到 42 秒且暂停，继续播放沿用 1.5 倍速。此外，真实 Chrome 对本地 WAV 解码播放约 6 秒，离页后刷新到约 6.1 秒且保持暂停；未外推到原生后台或长媒体。 |
| R4 | 主题/时间点改成同一 ORM 查询内 EXISTS + 范围过滤 + LIMIT；真实 SQLite 中 51 条较新发现内容不会遮掉旧收藏结果。 |
| R5 | provider 重建区分查询代次；旧分页不得写入新视图，失败只回补同查询被移除项；真实 Dio/Riverpod 交错响应回归。 |
| R6 | 整批先暂存，全部校验并写入关系后才发布内容寻址对象；失败清理暂存及本次新发布的未引用对象，保留已存在的共享文件。真实文件/SQLite 验证超限与中途发布失败。 |
| R7 | 仅按最近 200 条终态清理；保留 running、当前写入及仍被通知引用的 run。通知存在期间详情保持可达。 |
| R8 | 沿用事件至少一个成员的已确认规则；内容删除和成员移除共享检查，并在同一写事务内串行化。唯一成员删除返回 409；外键开启的并发内容删除只成功一项。 |
| A1 | 图集与主体媒体统一全局控制器，删除独立 Chewie 执行器及依赖。真实 Chrome 发现切页移除视频 DOM 会暂停；导航前捕获播放意图，动画移除完成后沿用同一控制器，人工暂停优先。页面返回与浏览器返回后继续、浏览另一音频不抢播、视频结束自动续播队列音频、暂停后返回及刷新、恢复后按 1.5 倍速继续播放均已通过。 |
| A2 | Agent/播放器状态改用已有 Freezed；完整代码生成、分析与 Flutter 回归已通过。 |
| A3 | 通知复用任务呈现标题、摘要和终态集合；删除逐内容 embedding 的冗余 worker 投影，保留真实 worker 健康与单次 run 各自职责。相关回归通过。 |
| A4 | 事件列表/搜索只加载成员内容 ID、标题与时间；真实 SQLite 验证正文未加载，详情仍可加载完整正文。 |
| A5 | Agent 历史 JSON/文本一次迁入 payload，保留原文；前端旧解析分支删除。删除文件 metadata 重复字段；保留仍服务入库的媒体 backfill 和契约规定的 manifest 刷新/切源。迁移幂等回归通过。 |
| U1 | 共享设置组改为标题与分隔线；图标/说明可选，开关同行，长操作显式换行。设置、模型、来源、账号和自动化页面四尺寸截图已生成，并按各尺寸代表页面复核信息层级。 |
| U2 | 七个明确设置分区；同步工作流只留自动化同步页，处理/分发/账号策略回到对应业务入口，旧设置别名删除。 |
| U3 | 清除常态 UI 中的布局、路由和内部实现解释，能力诊断折叠在模型配置之后。 |
| U4 | 账号详情改限宽单列，状态后立即给动作，能力紧凑呈现，问题修复折叠。 |
| U5 | 同步先呈现平台与操作；低频策略折叠，删除无选择空间的控件，调度生命周期与实际运行分开表达。 |
| U6 | 收藏筛选删除内层 Dialog；手机单层可滚动 sheet、桌面侧栏。四尺寸实际打开与退出弹层已通过。 |
| U7 | 规则按名称、条件、目标、审批/启用组织，高级项折叠；缺少目标直达管理。去除多余返回刷新，设置工具返回优先回到调用页面；四尺寸实际编辑、进入目标管理和浏览器返回均保留草稿。初次 DOM 语义值为空是探针误判，未为此添加重复草稿层。 |
| U8 | 内部笔记/文件详情和任务结果限宽单列；删除重复媒体标题、空封面/空简介，任务诊断折叠。新增代表性笔记、音视频和事件用于真实页面检查。 |
| U9 | 统一保存入口，附加信息折叠，删除固定快捷标签、标题装饰图标与收藏页重复添加入口。四尺寸真实键盘输入及类型切换保留正文和说明；390 宽缩短视口及 widget 的 320px 键盘 inset 验证按钮可达。真实文本和音视频批量保存已核对持久化。 |
| U10 | 搜索类型使用可见下拉，范围同行；清理空态与技术尾注。 |
| U11 | Agent 示例只填入可编辑草稿，发送由用户触发；会话次要操作收进菜单。防自动发送回归通过。 |
| U12 | 处理页只展示已实现的解析、归档、摘要、索引，策略开关不冒充健康；失败给出对应操作。 |

验证：后端完整常规套件 977 通过、4 跳过、8 项外部集成排除；最后 UTC 时间契约修正的 31 项相关回归通过。Flutter 完整回归 206 项通过；最后保存标题及分发筛选调整的 14 项相关回归通过，最终分析无问题。OpenAPI 检查 148 个端点、56 个动作契约通过。数量仅说明执行范围，不替代业务或设计验收。

测试精简：删除 `test_system_router_boundaries.py` 源码字符串检查和 `test_openapi_action_contracts.py` 重复模型名断言；保留 `scripts/check_openapi_docs.py` 契约门禁。空资产播放器恢复改为真实资产/manifest 回归，发现页参数 mock 改为交错响应回归；自动化开关改用实际 provider 与 Dio 边界，不再完整替换 controller；图片限制用真实 PNG 替代 `Image.open` mock；删除固定任务结果双栏的断言；导航测试复用已有 fixture，移除重复初始化与字体开关实现断言。正式回归未搬入本地诊断脚本。

实验库新增笔记 9、音频 10、视频 11、知识事件 1 作为代表性样本；真实浏览器保存另产生文本 12、批量音视频 13（资产 10、11）。正文、标签、说明经数据库核对，批量文件下载的 SHA256 与原文件一致。未清空既有数据；创建时暂停摘要、索引和分发，完成后恢复原配置。临时写入验收 API 已关闭，本地页面预览 API 只读且不启动 worker。真实模型、外部发送、账号操作和平台同步未执行；未提交、推送或部署。

额外同类整改：事件详情改为标题、描述、状态与成员数量，再呈现时间线；成员标题先于分类，内部笔记不显示“未知平台”。处理页删除全零指标和重复运行摘要。分发队列复用 Material ChoiceChip，状态文字和数量分别取宽并保持单行，删除挤占空间的图标；四尺寸实际切换三种状态，真实接口结果符合对应筛选。同步状态复用已有 UTC 序列化规则，修正同次运行在同步页和任务页相差 8 小时的问题；真实接口与四尺寸截图确认一致。

## 验证索引与保留边界

正式回归入口（均在完整套件中执行）：

复跑使用仓库根 `.venv/bin/python -m pytest backend/tests -q --no-cov`；前端在 `frontend/` 执行 `flutter test --no-pub`、`flutter analyze --no-pub`，并按 AGENTS 要求在沙盒外运行。OpenAPI 使用根虚拟环境执行 `scripts/check_openapi_docs.py`。外部集成未包含在默认后端执行范围内。

| 保护的行为 | 可重复证据 |
| --- | --- |
| R1、R2、A5：路径权限、确认唯一执行、历史消息迁移 | `backend/tests/test_agent_execution_boundaries.py` |
| R4、R6：范围先于 LIMIT、批次文件失败清理与共享对象保留 | `backend/tests/test_content_lifecycles.py` |
| R7：运行中任务和通知引用不被历史清理删除 | `backend/tests/test_background_task_state.py` |
| R8、A4：事件最后成员约束与并发删除、列表仅取摘要字段 | `backend/tests/test_api/test_knowledge_events.py` |
| R3、A1：稳定资产身份、manifest 恢复与播放会话 | `frontend/test/unit/media_source_session_test.dart`、`frontend/test/widget/global_player_test.dart` |
| R5：分页与切换查询交错、失败回补归属 | `frontend/test/unit/discovery_feed_provider_test.dart` |
| 保存、导航、设置、账号、规则、任务、搜索与 Agent 的关键交互 | `frontend/test/widget/capture_sheet_test.dart`、`navigation_shell_test.dart`、`settings_page_responsive_test.dart`、`account_detail_page_test.dart`、`automation_page_test.dart`、`task_result_page_test.dart`、`search_page_test.dart`、`agent_confirmation_recovery_test.dart` |

本地浏览器诊断保留在被忽略的 `backend/manual_tests/`：`verify_browser_capture.py`、`verify_browser_playback.py`、`verify_video_queue.py`、`verify_ui_interactions.py`、`verify_design_revision.py`、`refresh_sync_evidence.py`、`verify_queue_filters.py`。这些材料记录了真实本地 Web → API → SQLite/文件存储和 Chrome 解码行为，不作为外部平台验收或新增 CI 基础设施。对应本机执行日志在 `/tmp/vaultstream-browser-capture.log`、`/tmp/vaultstream-video-history.log`、`/tmp/vaultstream-ui-interactions.log`、`/tmp/vaultstream-sync-time-live.log`；持久截图见下节。

保留媒体资产身份和候选源契约、人工编辑与知识事件边界、持久化单次任务及 worker 健康状态：这些分别承担数据身份、人工判断、任务追踪和服务生命周期职责。媒体 backfill 仍用于当前解析入库；签名过期刷新和来源切换属于现行媒体契约。没有引入新的框架、双播放器或运行时历史格式猜测。

验证边界：4 项后端跳过均缺少 LLM API Key；8 项外部集成测试未执行。未验收真实模型生成、外部同步/发送、账号登录或生产部署。Web 的手机/横屏/平板/桌面尺寸已检查；没有把它写成原生设备、系统软键盘、原生后台播放、PiP、系统媒体控件、长媒体或睡眠计时器的实机验收。浏览器媒体使用本地 60 秒 WAV 与约 10 秒 WebM，未替换浏览器解码器。

## 整改后设计证据

实际 Web 页面覆盖 390×844、844×390、768×1024、1200×900；每个尺寸生成模型、来源、同步、账号、处理、规则、搜索、内容、事件、收藏、动态、分发、通知、任务和 Agent 截图。设计复核聚焦主内容与动作、次要配置权重、空态/未配置/失败的下一步；交互补查覆盖筛选弹层、保存草稿、键盘遮挡、短横屏导航、规则返回、媒体离页与刷新。

| 页面与整改重点 | 整改前 | 整改后 |
| --- | --- | --- |
| 手机账号：连接操作紧接状态 | ![前](../assets/2026-09-06-implementation-review/before/account-zhihu-390.png) | ![后](../assets/2026-09-06-implementation-review/after/account-zhihu-390.png) |
| 手机模型设置：模型优先，诊断折叠 | ![前](../assets/2026-09-06-implementation-review/before/settings-ai-390.png) | ![后](../assets/2026-09-06-implementation-review/after/settings-ai-390.png) |
| 手机同步：平台操作优先，策略后置 | ![前](../assets/2026-09-06-implementation-review/before/sync-390.png) | ![后](../assets/2026-09-06-implementation-review/after/sync-390.png) |
| 手机规则：匹配与目标优先 | ![前](../assets/2026-09-06-implementation-review/before/rule-new-390.png) | ![后](../assets/2026-09-06-implementation-review/after/rule-new-390.png) |
| 手机任务：结果与操作先于诊断 | ![前](../assets/2026-09-06-implementation-review/before/task-390.png) | ![后](../assets/2026-09-06-implementation-review/after/task-390.png) |
| 桌面分发：队列筛选数量完整呈现 | ![前](../assets/2026-09-06-implementation-review/before/distribution-1200.png) | ![后](../assets/2026-09-06-implementation-review/after/distribution-1200.png) |

补充：![横屏筛选](../assets/2026-09-06-implementation-review/after/filters-844.png)、![手机保存](../assets/2026-09-06-implementation-review/after/capture-390.png)、![平板音频详情](../assets/2026-09-06-implementation-review/after/detail-audio-768.png)、![横屏事件](../assets/2026-09-06-implementation-review/after/event-844.png)、![规则返回后草稿](../assets/2026-09-06-implementation-review/after/rule-draft-return-390.png)、![桌面媒体队列](../assets/2026-09-06-implementation-review/after/video-queue-1200.png)。

## 后续 UI 结构优化（2026-09-06）

针对调试文案、填充式空态之后继续进行结构整改：收藏库手机与短横屏使用单列，宽屏保留多列；实际缩略图置于文字旁，删除类型图标大占位和固定媒体高度。搜索分组采用列表行，支持清除查询并同步移除旧结果。Agent 合并输入与发送区域，空输入禁用发送，回车换行，删除重复停止按钮和逐条消息装饰图标。详情正文删除额外淡入层，修复浏览器中持续半透明的正文，并收紧段落间距。

- `flutter analyze --no-pub`、6 项现有回归与 Web JS 构建通过；临时四尺寸/两倍字体/长元信息/选择交互验收曾发现溢出，修复后通过，脚本已删除。
- 浏览器使用实验库只读服务，禁止写入且不启动后台 worker。实际检查收藏进入详情再返回、搜索提交和清除、Agent 多行草稿及横屏切换，未发送模型请求。
- 截图：![收藏优化前](../assets/2026-09-06-ui-structure/collection-before-390.png)、![收藏优化后](../assets/2026-09-06-ui-structure/collection-after-390.png)、![平板收藏](../assets/2026-09-06-ui-structure/collection-768.png)、![桌面收藏](../assets/2026-09-06-ui-structure/collection-1200.png)、![详情优化前](../assets/2026-09-06-ui-structure/detail-390.png)、![详情优化后](../assets/2026-09-06-ui-structure/detail-after-390.png)、![手机搜索](../assets/2026-09-06-ui-structure/search-390.png)、![桌面搜索](../assets/2026-09-06-ui-structure/search-1200.png)、![横屏 Agent](../assets/2026-09-06-ui-structure/agent-844.png)。
- 这是上述页面的专项验收，不代表所有页面全状态的设计验收。真实设备软键盘、系统返回手势、模型流式回复和外部平台仍未在本轮验收。

## 原始审查：结论与边界（整改前）

以下正文保留 2026-09-06 整改前的复现、代码位置与建议，包含已被本次修复替换或删除的路径；不代表当前工作区结论。当前状态以本文顶部处理表和验收证据为准。

当前不能按“已全面完成”验收。问题不只是行数：确认执行缺少原子领取、播放器资产身份与临时地址耦合、列表异步结果缺少查询归属，以及数据库与文件/关联对象之间的生命周期未闭合。部分回归测试只证明调用或字段存在，不能证明对应用户流程成立。

审查覆盖当前工作区的主要新增/修改领域：捕获与内容编辑、媒体资产与播放、搜索与知识事件、发现列表、后台任务与通知、Agent 控制、前端入口和测试方式。结合当前代码、与 HEAD 的差异、真实 SQLite/文件存储探针、Flutter 状态复现和 Web 页面截图。不是对每行代码、每个平台或每个原生设备的正确性保证。

工作区包含此前模型及用户已有修改，不能把整个 diff 都归因于本次审查。Agent 并发确认问题在 HEAD 已存在；本轮改造仍未解决它。API bridge 的路径规范化缺口也不能简单归因于新增 mutation 白名单；本轮收窄写操作有价值，但不足以证明整个 bridge 安全。

没有执行真实模型调用、外部发送或平台同步。本次未修改产品代码、未提交、未推送、未部署。只增加审查报告和忽略目录内的诊断材料，生成本地 Web 构建与截图。

## 已确认问题

P1 表示应优先处理的能力/控制边界缺陷，P2 表示正常使用中会出现的正确性或生命周期问题。

### R1 / P1：Agent 只读白名单可被路径规范化绕过

- 代码：[api_bridge.py](/Users/ienone/coding/vaultstream/backend/app/services/agent/tools/api_bridge.py:198)、[前缀判断](/Users/ienone/coding/vaultstream/backend/app/services/agent/tools/api_bridge.py:265)。
- 校验的是原始字符串；HTTPX 随后会消除路径中的 `..`。`/api/v1/contents/../agent/sessions` 通过 contents 白名单，实际访问 `/api/v1/agent/sessions`。
- 复现使用真实 `_api_get_tool`、HTTPX ASGITransport 和仅有目标路由的本地 FastAPI app，返回 200 且 `forbidden_route_reached=true`。未访问真实 Agent SSE、未触发真实模型。
- 影响：明确禁止暴露的 Agent 路由可达；同类路径可指向 Agent SSE，不能把“GET”当成无副作用保证。尚未证明绕过收窄后的 mutation 模板，不作该断言。
- 方向：校验与实际请求必须使用同一规范化路径；拒绝模糊/跨段路径，并对规范化后 method + path 判权。保留少量经过真实 URL 解析的边界测试。

### R2 / P1：同一个 Agent 确认可执行两次

- 代码：[decide_confirmation](/Users/ienone/coding/vaultstream/backend/app/services/agent/service.py:507)、[执行前状态赋值](/Users/ienone/coding/vaultstream/backend/app/services/agent/service.py:576)。
- 两个数据库 session 都能先读到 pending。将 ORM 对象改成 approved/running 不是原子领取，副作用之前没有条件更新并提交的排他状态转换。
- 复现使用真实 ORM、两个独立 session 和真实 service/registry；外部工具边界替换成可计数的本地 handler。两个请求都返回 completed，handler 执行次数为 2。不是两次真实外部发送。
- 影响：双击、重复请求、多个客户端批准同一项，可能重复执行不可逆工具。
- 方向：在执行前原子领取 pending confirmation，仅领取成功者执行；领取/执行/完成状态清晰分离。外部动作若有原生幂等键应复用，不另造通用重试框架。
- 归属：HEAD 已有缺陷，本轮增加通知和恢复入口后仍然存在。

### R3 / P1：播放器重启恢复拿不到媒体资产，无法重新取得播放地址

- 代码：[快照序列化](/Users/ienone/coding/vaultstream/frontend/lib/features/player/global_playback_controller.dart:54)、[资产查找](/Users/ienone/coding/vaultstream/frontend/lib/core/media/media_source_session.dart:39)、[manifest 加载](/Users/ienone/coding/vaultstream/frontend/lib/features/player/global_playback_controller.dart:360)。
- 快照清除签名 URL 和 sources 是正确方向；但恢复后的 session 又通过“当前 source URL”查找资产。sources 为空时 asset 恒为 null，加载 manifest 直接返回。
- 复现：真实 PlaybackRequest JSON 往返后，持有资产 id=7 的 MediaSourceSession 返回 `asset=null`；预期保留身份的 Flutter 断言失败。不需要模拟网络即可证明无法发起请求。
- 影响：队列/倍速等字段恢复了，但核心媒体无法恢复播放。
- 方向：稳定资产身份独立于可过期来源存在。空候选应仍能按 ID 获取 manifest；不要靠恢复旧签名 URL 兜底。
- 测试缺口：[已有恢复测试](/Users/ienone/coding/vaultstream/frontend/test/widget/global_player_test.dart:204) 输入空 URL、没有资产，且断言 initialized=false，未检验重新请求 manifest 或实际可继续播放。
- 文档不一致：[媒体渲染说明](/Users/ienone/coding/vaultstream/docs/frontend/components/media-rendering.md:23) 将按资产 ID 重新读取 manifest 写成当前能力，此路径实际不成立。

### R4 / P2：主题/时间点搜索先截断候选，再筛选范围，导致漏结果

- 代码：[主题 SQL](/Users/ienone/coding/vaultstream/backend/app/services/search_service.py:417)、[时间点 SQL](/Users/ienone/coding/vaultstream/backend/app/services/search_service.py:323)。
- 原始 SQL 对全部内容匹配后 LIMIT，随后 ORM 查询才应用 library/discovery、平台、日期和解析状态。
- 复现：1 条较早的匹配收藏、51 条较新的匹配发现内容，候选上限 50；库内明明有 1 条，精确主题查询返回 0。真实 SQLite JSON 查询，无 embedding mock。
- 影响：数据量增加或选择筛选条件后，精确主题/时间点补充结果漏召回。最终统一搜索是否完全为空还取决于另一条语义搜索路径，不能一概而论。
- 方向：将约束放在同一次候选查询、LIMIT 之前；复用现有筛选表达式。单纯调大 LIMIT 不是修复。

### R5 / P2：发现页旧分页结果覆盖新筛选视图

- 代码：[showView/loadMore](/Users/ienone/coding/vaultstream/frontend/lib/features/discovery/providers/discovery_feed_provider.dart:46)。
- “最近”加载第二页时切换到“稍后处理”，新视图先返回；旧分页后返回，将捕获的旧 items 写回当前 state。view 属性与显示内容不再一致。
- 复现使用真实 Riverpod provider 和 Dio，只控制 HTTP 响应顺序：稍后列表预期 `[90]`，实际被覆盖成 `[1, 2]`。Flutter 断言失败。
- 方向：以查询条件作为 provider/state 身份，或给请求增加足够简单的版本校验。取消旧请求可配合使用，但不能单靠 loading 布尔值。
- 相邻的整表乐观回滚也会恢复过时快照，值得在同一修复中覆盖；本次没有把这一推导单独计作已复现问题。

### R6 / P2：多文件捕获中途失败留下孤立文件

- 代码：[create_files_capture](/Users/ienone/coding/vaultstream/backend/app/services/content_service.py:388)。
- 文件逐个写入正式存储后才统一创建内容记录。第二个文件超限，前一个已完成对象不会回滚；当前 put_stream 只清理自己正在写的临时文件。
- 复现用真实 LocalStorageBackend，第一个文件 3 字节、第二个超过 3 字节限制：请求失败，存储仍有 1 个、3 字节的孤立对象。
- 方向：明确批次的暂存/发布边界，或记录本次新建对象并做引用安全的清理。内容寻址对象可能被其他内容共享，不能在异常分支无条件删除前面所有 key。

### R7 / P2：历史清理会删除仍在运行的任务

- 代码：[_upsert_run 清理](/Users/ienone/coding/vaultstream/backend/app/services/background_task_state.py:296)。
- 每种任务只保留最近 200 条，删除条件不排除 running。
- 复现：最早一条 running、其后 199 条 success，再创建一条新运行，最早 running 记录被删除。
- 影响：正在执行的任务在详情中消失；其后终态更新可能重建缺少原始元数据的记录。通知保留时长与任务按数量删除也不一致，详情链接生命周期没有统一。
- 方向：只清理终态记录，明确任务与通知引用的保留规则；没有必要为此增加一个复杂调度框架。

### R8 / P2：删除内容绕过“事件至少一个成员”的约束

- 代码：[移除事件成员](/Users/ienone/coding/vaultstream/backend/app/services/knowledge_event_service.py:188)、[删除内容](/Users/ienone/coding/vaultstream/backend/app/services/content_service.py:776)、[成员外键](/Users/ienone/coding/vaultstream/backend/app/models/knowledge_event.py:103)。
- 事件 service 禁止移除最后一个成员，但删除内容会经外键 CASCADE 清除成员，保留空的 active 事件。
- 复现使用开启 foreign_keys 的真实 SQLite 和 ContentService.delete_content：删除唯一成员内容后，事件仍存在，成员数为 0。通知副作用使用本地 sink，事件 outbox 写入诊断数据库。
- 方向：统一产品规则，选择明确阻止、归档空事件或允许并正确表达空事件；在内容删除与事件操作两条入口一致执行。不要只在 UI 上禁用一个按钮。

## 架构与重复实现

### A1：播放器复用只做了一半，应收敛执行逻辑

内嵌 [VideoPlayerWidget](/Users/ienone/coding/vaultstream/frontend/lib/features/collection/widgets/common/video_player_widget.dart:32) 和应用级 [GlobalPlaybackController](/Users/ienone/coding/vaultstream/frontend/lib/features/player/global_playback_controller.dart:180) 各自维护控制器、初始化代次、manifest 刷新、过期刷新、失败切源和运行期错误恢复。MediaSourceSession 只复用了候选数据状态，没有统一执行路径。

前者仍由 MediaGalleryItem 实际调用且使用 Chewie；后者另有自定义 VideoPlayer 控件。不是死代码，也不是把某个文件删掉就完成收敛。不同展示形态可以保留，但不应各写一次相同的媒体生命周期。应先确定内嵌预览与全局播放的产品边界，再共享最小播放执行器或统一控制器。

现有 Chewie/video_player 能覆盖基础视频展示/控制，队列、资产身份、章节和跨页会话属于本项目业务，不能笼统说全部应该换成第三方播放器。两个执行模块共约 1,074 行，不等于其中 1,074 行都可删。

### A2：已有 Freezed，却又手写相同性质的状态样板

AgentViewState 和 GlobalPlaybackState 分别手写 copyWith、Object sentinel 和 nullable 字段强转；项目已有 Freezed/json_serializable，Discovery、Content 等模型正在使用。

应沿用既有工具处理相同性质的不可变状态，减少手工字段同步和测试负担。不是再引入一个状态框架，也不是为了少数几十行强制重写所有小对象。生成代码不应与手写业务代码用相同口径评价复杂度。

### A3：任务名称、状态和结果说明重复维护

[task_run_presentation.py](/Users/ienone/coding/vaultstream/backend/app/services/task_run_presentation.py:7) 与 [notification_inbox.py](/Users/ienone/coding/vaultstream/backend/app/services/notification_inbox.py:25) 各有任务中文名映射、状态集合和结果解释。已有同一 task 对应“重新解析内容/内容重解析”“重建语义索引/语义重建”等差异，通知也没有直接复用已有 presentation 摘要。

后台任务聚合状态又写在 SystemSetting，单次运行在 BackgroundTaskRun；两者独立提交。worker 健康与单次运行确实可能是不同概念，不能强行合表，但必须明确各自唯一负责什么，不应复制同一个事实。

优先复用现有任务呈现入口，分清 worker 状态和 run 状态，而不是加一个万能任务注册中心或统一工作流引擎。

### A4：知识事件列表为摘要读取完整内容图，查询形态偏重

[list_events/search_events](/Users/ienone/coding/vaultstream/backend/app/repositories/knowledge_event_repository.py:46) 加载所有成员及其完整 Content；列表摘要只需成员数量、发生时间和最新标题，却把正文、rich_payload 等也读入内存。selectinload 避免了 N+1，但不等于按需要取数。

建议列表查询按必要字段/聚合取摘要，详情保留完整关系。当前实验数据规模小，没有测出具体延迟，也不宣称已发生性能事故；这是有明确代码依据的读放大。

### A5：兼容分支应逐项核对数据来源，不按关键词机械删除

Agent 的 `_storedToolEvent` 同时解释 payload、JSON 字符串和旧纯文本；媒体 backfill 也识别历史字段。前者对应旧消息的真实历史格式，后者还服务于解析结果入库，不能看到“legacy/backfill”就整块删掉。

既然数据库是实验用，若决定不保留旧记录，可移除仅为历史格式存在的路径；若保留，则用一次迁移结束兼容窗口。与此不同，签名过期刷新、来源失败后按 manifest 顺序尝试候选，是已定义媒体契约的一部分，不属于应无条件删除的防御性编程。

## 测试价值审查

不以 mock 数量判刑，判断测试是否把被验证的能力替换掉，以及是否能发现真实失败。

- 播放器恢复测试没有播放来源，也不检查 manifest 请求，因此不能作为恢复能力证据；R3 给出了反例。
- 发现页现有测试只检查查询参数 state=snoozed，没有交错响应，漏掉 R5。
- [router 边界测试](/Users/ienone/coding/vaultstream/backend/tests/test_system_router_boundaries.py:7) 搜索源码字符串，例如 ConfigService、asyncio.create_task，不能证明职责或策略正确；注释会误伤、别名可绕过。可用简明协作规范替代，关键策略由行为测试保护。
- [OpenAPI 动作测试](/Users/ienone/coding/vaultstream/backend/tests/test_openapi_action_contracts.py:12) 逐项固定响应模型 `$ref` 名称，且与检查脚本共享目录。可保留契约完整性检查，但不应把模型名稳定或几十个参数化 case 当成几十项业务验收。
- 前端多处完整替换 controller、Dio 后只检查调用参数；这能保护 UI 连线，不证明实际播放器、网络错误流程或数据库状态。保留有独立价值的少量连线测试，减少重复 fixture 和同构断言。
- 外部模型、平台发送使用边界 fake 是合理的；确认原子性、数据库查询、真实文件清理、查询响应竞态应尽量运行实际实现。

整改时将 R1–R8 的必要回归放入正式 tests，使用共用最小 fixture。不要把本次诊断目录整体加入 CI，也不要为了减少测试数量删掉权限、持久化和关键流程保护。

## UI/UX 设计复审：替代上一轮运行与布局抽查

2026-09-06 用户指出上一轮只按“可以工作”评价前端。本节重新按任务优先级、信息组织、文字必要性、图标语义、控件选择与操作成本审查。结论：当前前端不能通过设计验收；问题具有跨页面、共享组件层面的规律，不是几个孤立的颜色/字号问题。

### 范围与证据

以当前 Web 构建访问实验数据库的只读 API，关闭后台 worker，未发送模型请求、未保存表单、未触发同步/推送。设置响应中的凭据在截图前替换为审查占位值。

采集 19 个路由状态在 390×844、1200×900 下的页面及部分滚动区域：动态、收藏、笔记/文档详情、自动化总览/同步/分发/处理阶段、规则新建、设置入口及三个分区、账号列表/知乎详情、搜索空态、Agent 空会话、消息和任务结果。另实际打开捕获及收藏筛选 surface，查看规则、同步、账号页下半部。代表性页面逐图审视并核对对应布局代码；不是仅判断控制台是否出现 overflow。

实验库没有知识事件和完整的真实长文/长视频样本。本次未作事件实页、多媒体长内容、原生软键盘、全部横屏/平板、辅助技术的设计验收；这些没有被判为合格。短笔记产生的大块空白、验收样本的无效封面不作为布局故障证据。

### U1：共享设置行强制制造图标、说明和额外高度

- 证据：[SettingTile](/Users/ienone/coding/vaultstream/frontend/lib/features/settings/presentation/widgets/setting_components.dart:70) 强制要求 subtitle 和 icon；只要有 trailing 且宽度小于 formMaxWidth，就把尾部控件另起整行，没有区分小 Switch 和长表单。![手机 AI 设置截图](/Users/ienone/coding/vaultstream/backend/manual_tests/audit-ui-design/settings-ai-390.png)。
- 现象：一个开关由图标底板、加粗标题、说明、空隙、右下开关构成，约占 140–160 像素；390×844 首屏只看到约五项。标题旁本来可以放下的开关与标题被拆开。
- 决策：图标、副标题改为按必要性使用，不作为每行默认装饰；普通开关与标题同排，仅长控件或确有需要的帮助文本换行。不能只逐页减 padding，否则下一页仍会复发。
- 验收：用户能连续扫描标签及开关；必要触控面积不缩小，字体放大时仍允许合理换行。不能用“无溢出”代替这一验收。

### U2：设置分类失真，已拆出的收藏同步工作流又复制回来

- 证据：[设置分区定义](/Users/ienone/coding/vaultstream/frontend/lib/features/settings/settings_page.dart:29)、[AutomationTab](/Users/ienone/coding/vaultstream/frontend/lib/features/settings/presentation/tabs/automation_tab.dart:27)、[立即同步等操作](/Users/ienone/coding/vaultstream/frontend/lib/features/settings/presentation/tabs/automation_tab.dart:807)。
- “AI 与发现”实际包含解析队列、分发模式、Cookie 保活、收藏调度、同步间隔、单次上限、手动同步、最近任务和运行记录；模型配置却排在这条长列表后部。分发模式不在分发主入口，账号保活不在账号语境，查找靠猜。
- `/automation/sync` 已有同步策略、预览、运行和重试，设置又维护一套同类操作。这不只是文案不好，也是工作流重复。
- 动态空态的“管理信息来源”只跳到 `/settings?tab=automation` 的顶部，用户首先看到的是一堆开关，而不是来源列表：[跳转代码](/Users/ienone/coding/vaultstream/frontend/lib/features/dashboard/dashboard_page.dart:223)。
- 决策：收藏同步操作和完整运行状态只留在自动化同步页；设置按用户寻找对象组织低频参数。特定动作入口直接定位目标区或独立对象页，不让用户再翻长表单。不为修分类再增加第二份控制面。
- 文档不一致：settings.md 声称“不把自动化领域操作复制到设置中”，实际上述重复仍存在，不能继续写成已完成收敛。

### U3：设计说明和实现解释进入常态 UI

以下是页面字面文案，不是用户内容；应删除或移到真正需要时才出现的帮助说明：

| 页面 | 当前文字 | 处理 |
|---|---|---|
| 手机设置入口 | “移动端先进入分区列表，再打开对应详情，避免在一个页面里堆叠过多表单。” | 删除。这是在解释设计者如何布局。 |
| 桌面设置侧栏 | “低频配置集中在这里；日常任务和异常处理会进入通知中心或自动化下钻。” | 删除。“低频”“下钻”不是用户当前需要的信息。 |
| 处理阶段 | “按内容进入资产库后的真实执行阶段查看状态；配置与运行结果分别进入设置和任务页。” | 删除常驻段落；标题、状态与动作应能自行表达职责。 |
| 搜索页底部 | “内容使用混合语义检索；人物和主题来自当前命中内容，时间点只来自带明确媒体与秒数的章节或转写片段。” | 移出常驻底栏，必要时置于对应类别的简短帮助中。 |
| 账号详情 | “这些是 VaultStream 后端报告的可用能力，不代表平台授予了未列出的权限。” | 不向所有用户展示内部 contract 澄清；只在实际授权流程表达真实权限和风险。 |
| 同步策略 | “支持 run 级失败重试，也可在结果摘要中重试单条失败候选。” | 失败项直接提供重试；开发术语移出常态策略清单。 |

来源：[设置](/Users/ienone/coding/vaultstream/frontend/lib/features/settings/settings_page.dart:149)、[搜索](/Users/ienone/coding/vaultstream/frontend/lib/features/search/search_page.dart:247)、[账号](/Users/ienone/coding/vaultstream/frontend/lib/features/accounts/account_detail_page.dart:218)、[同步](/Users/ienone/coding/vaultstream/frontend/lib/features/automation/widgets/favorites_sync_automation_panel.dart:317)。

“删除内容是否影响本地文件”“开启后是否发生外部发送”等会影响用户决定的说明应保留，不能把必要风险提示与这些内部说明一起删除。

### U4：账号详情主操作在说明和能力卡之后，手机首屏无法连接

- ![390 宽截图](/Users/ienone/coding/vaultstream/backend/manual_tests/audit-ui-design/account-zhihu-390.png) 中，未连接账号先展示大状态卡、“能力与状态”及说明、四张能力卡、最近同步，首屏末尾才到“账号操作”标题，连接按钮在屏外。
- [布局代码](/Users/ienone/coding/vaultstream/frontend/lib/features/accounts/account_detail_page.dart:165) 先 overview 后 controls；[能力卡](/Users/ienone/coding/vaultstream/frontend/lib/features/accounts/account_detail_page.dart:294) 固定 220 宽，手机不足以两列却也不填满整行，造成四张孤立窄卡与大量右侧空白。
- 决策：未连接状态的“连接账号”进入标题/状态附近；已连接状态再显示检查、同步和低频退出。能力列表用紧凑状态行，不把四个短值都做成独立卡片；没有实际问题时不要预先占一整栏讲修复步骤。

### U5：同步页信息顺序倒置，并用错误控件表达固定规则

- ![手机同步页](/Users/ienone/coding/vaultstream/backend/manual_tests/audit-ui-design/sync-390.png) 首屏被总览、统计胶囊、操作按钮、长同步策略占据，平台列表在其后；当前 0 个平台启用，却未优先展示连接/启用平台的下一步。
- 同步间隔和单轮上限在总览、策略摘要、编辑行反复出现；`2026-09-05T14:55:39.784750`、cursor、run 等技术表示直接暴露。
- [三个策略下拉](/Users/ienone/coding/vaultstream/frontend/lib/features/automation/widgets/favorites_sync_automation_panel.dart:277) 各只有一个选项：全部收藏、仅拉取当前页、保留本地收藏。控件看起来可以选择，实际上没有选择空间。
- [状态颜色](/Users/ienone/coding/vaultstream/frontend/lib/features/automation/widgets/favorites_sync_automation_panel.dart:149) 将所有 running=false 都用 error 色显示“自动任务未运行”，没有区分空闲、未启用和异常。是否健康不能仅由有没有正在执行决定。
- 决策：平台及其阻塞优先，低频同步策略折叠；固定策略改为必要时的只读说明或不显示；时间格式化；只有失败才用异常色。相同数据只在一个最有用的位置表达。

### U6：收藏筛选把 Dialog 嵌入 bottom sheet，双层容器吞掉空间

- ![截图](/Users/ienone/coding/vaultstream/backend/manual_tests/audit-ui-design/filters-390.png)：外层已有 sheet 圆角和拖动柄，内部又出现窄 Dialog 的圆角、边距、头部和分隔线，390 宽实际表单内容区约 262 宽。
- 原因：[页面打开 sheet](/Users/ienone/coding/vaultstream/frontend/lib/features/collection/collection_page.dart:375)，传入的 [FilterDialog 自己又返回 Dialog](/Users/ienone/coding/vaultstream/frontend/lib/features/collection/widgets/dialogs/filter_dialog.dart:209)。桌面 side sheet 路径同样复用这个带外壳对象。
- 决策：只保留一个 surface 外壳，复用不带 Dialog/Sheet 的筛选表单内容。筛选重置使用“重置”文字，不用红色刷新图标让用户猜它会刷新还是清空。

### U7：规则编辑先展示底层参数，匹配内容和发送目标反而在下方

- ![首屏](/Users/ienone/coding/vaultstream/backend/manual_tests/audit-ui-design/rule-new-390.png)、![滚动后](/Users/ienone/coding/vaultstream/backend/manual_tests/audit-ui-design/rule-new-lower-390.png)。AppBar 和表单头重复“创建分发规则”；表单再放一个大齿轮图标。首屏先安排描述、NSFW、优先级、频率、时间窗口、审批，标签匹配和推送目标在下方。
- [源码](/Users/ienone/coding/vaultstream/frontend/lib/features/automation/widgets/distribution_rule_editor.dart:123) 体现同样顺序。没有目标时，仅提示“请先在 Bot 群组页添加或同步”，没有就近修复入口。
- 决策：按“哪些内容 → 发到哪里 → 是否审批 → 创建”组织，频率/时间窗口/优先级进入高级区。只保留一个页面标题；减少每个输入框的装饰性前缀图标；缺少目标时给直接入口并保留草稿。

### U8：读取页和结果页都过度套卡片，内容与诊断权重失衡

- ![笔记详情](/Users/ienone/coding/vaultstream/backend/manual_tests/audit-ui-design/detail-note-1200.png) 顶部和侧栏重复 UNIVERSAL；人工保存的笔记显示“未知作者”，右侧单个标签也占一整块容器。空白正文长度来自实验数据，不作缺陷；重复元信息和不适用的作者占位才是问题。
- ![任务结果](/Users/ienone/coding/vaultstream/backend/manual_tests/audit-ui-design/task-390.png) 把四个 0 分别做成整行小卡片并加彩点，“没有新内容”被扩展为大段统计；Run ID、内部任务名又常驻后面。[_ResultSection](/Users/ienone/coding/vaultstream/frontend/lib/features/dashboard/task_result_page.dart:499) 统一在小于 520 宽时将任意短指标全宽排列。
- 决策：元信息只出现一次，人工笔记不硬套外部平台作者模板；任务用一句结果摘要和紧凑指标，诊断字段收起。宽屏不是所有详情都必须分成同样的两栏。
- 消息列表的“任务已完成，可查看运行结果”没有提供具体结果，不能用增加一张卡片补救；应复用已有业务摘要，让用户先判断是否需要点入。

### U9：捕获表单把可选整理动作摆成必经流程，入口命名也不统一

- ![截图](/Users/ienone/coding/vaultstream/backend/manual_tests/audit-ui-design/capture-390.png)：保存链接时常驻两行八个固定快捷标签、自定义标签、保存说明和 NSFW 开关。[_quickTags](/Users/ienone/coding/vaultstream/frontend/lib/features/collection/widgets/dialogs/add_content_dialog.dart:94) 是硬编码的“待看/收藏/学习/工作/灵感/有趣/技术/设计”，不是用户实际标签或最近使用项。
- 收藏页还同时有底部“采集”和浮动“添加内容”，打开后标题又叫“捕获内容”；同一动作三个名字，两处入口争夺注意力，浮动按钮遮住列表可见区域。
- 决策：主路径只要求输入内容并“保存”；说明、标签、敏感标记进入清楚可达的可选区，已有用户设置应保留。快捷标签取真实使用情况或移除默认清单；统一动作名并收敛同屏重复入口。具体敏感标记策略不因视觉精简被取消。

### U10：搜索把类型控件和内部解释置于内容之上

- ![手机截图](/Users/ienone/coding/vaultstream/backend/manual_tests/audit-ui-design/search-390.png)：类型横排只露出全部/内容/事件/人物，主题和时间点需要横滑，却没有明显未显示项提示；内容范围又占另一排。底部固定技术说明，空态还有一个重复搜索图标和大标题。
- 决策：主搜索框与结果先清楚，类型采用可发现的滚动标签或明确的类别选择；内容范围改成简洁入口。移除常驻技术解释和无额外价值的空态装饰。结果中的人物/主题聚合应保留事实边界，但不必对所有查询先讲一段实现原理。

### U11：Agent 示例按钮表达的动作与实际发出的请求不一致

- ![Agent 页面](/Users/ienone/coding/vaultstream/backend/manual_tests/audit-ui-design/agent-1200.png) 显示“创建规则”；[实际 handler](/Users/ienone/coding/vaultstream/frontend/lib/features/agent/agent_page.dart:606) 直接发送“为 #AI 标签创建一条需要审批的自动推送规则”。“检索最近的 AI Agent 内容”实际请求也额外指定“安全风险”。这些条件不是按钮文字表达的用户选择。
- [_sendPrompt](/Users/ienone/coding/vaultstream/frontend/lib/features/agent/agent_page.dart:162) 直接调用 controller 发送，不只是填入草稿。本次没有点击这些按钮，没有调用真实模型；工具副作用是否批准仍受确认机制约束，不宣称点击就绕过确认创建规则。
- 决策：示例填入可编辑输入框再由用户发送，或完整表达具体示例；会话列表中的 active 等内部状态不常驻给用户看。重做、刷新、删除不应只靠顶部相近的小图标区分，低频危险操作进有文字的菜单。

### U12：处理页和全局组件混淆“配置、能力、运行、失败”

- ![处理页](/Users/ienone/coding/vaultstream/backend/manual_tests/audit-ui-design/processing-1200.png) 把“摘要 / OCR / 转写”打包成一张卡，再说明 OCR/转写没有生产任务；“媒体归档”仅由策略开启就显示“正常”。这两个状态并非同一性质：[状态构造](/Users/ienone/coding/vaultstream/frontend/lib/features/automation/widgets/processing_automation_panel.dart:169)。
- 错误行直接展示 `max_attempts_reached: RetryableAdapterError`；多个阶段都只有相同的“配置”按钮，跳往宽泛设置分区，用户仍需再次寻找目标。
- 决策：主视图只呈现真实可用阶段和需要处理的对象；没有实现的能力不靠常驻卡片加免责声明占位。策略明确标“已启用/已关闭”，最近执行显示独立结果；失败先给用户能理解的原因与具体下一步，技术错误在详情可查。
- 自动化总览仍可保持已确认的三个领域入口，不需要借这次整改恢复跨域统计仪表盘；缩减入口卡的装饰图标、指标胶囊与重复说明即可。

### 共同设计决策与关闭条件

1. 先纠正页面任务顺序和唯一主入口，再调整视觉细节；不能以统一颜色/圆角代替信息架构。
2. 图标仅用于识别、操作、状态或必要导航，不要求每个标题/字段/指标都有图标底板。图标和文字重复且无扫描收益时删除图标；危险动作和含混动作不能只留图标。
3. 卡片表示独立对象或有明确边界的分组，不把页面、分组、单行短指标全部各套一层。选中态、可点击入口、只读状态胶囊应能区分。
4. 常态文字帮助用户决定或完成动作，不解释开发者的实现和页面布局；不能为了维护“准确口径”把验收免责声明贴满界面。
5. 在真实内容、空数据、未配置和失败状态下分别审视首屏：用户能立即知道当前位置、当前结果和下一步；低频配置不压过主操作。
6. 手机不是桌面所有卡片逐个竖排；窄屏须重新组合短指标、主操作、辅助信息与容器。键盘、长文字和大字号另行验证。
7. 验收同时要求功能正确与界面清晰，不再把这些设计问题降格为“可以工作之后再说”的美化项。修复应按领域和共享组件做减法，本次尚未实施。

## 哪些应保留

媒体资产/变体与签名访问、知识事件/成员的独立业务语义、人工编辑与解析候选分离、任务运行记录和持久通知、统一内容捕获入口，都解决真实产品需求。它们的存在不等于过度设计；应修正边界与状态转换，再删除重复执行路径。

新增的全文/主题/人物/时间点搜索入口、播放队列/倍速/书签、消息中心、Agent 会话和确认恢复等有实现代码，但不能把“入口和模型齐全”写成“完整功能验收”。尤其播放器恢复和确认执行已被当前探针否定。

## 复现与验证记录

- `.venv/bin/python backend/manual_tests/audit_state_invariants.py`：实际 SQLite/ORM/ASGI 验证 R1、R2、R4、R7、R8，输出分别为可达、执行 2 次、返回 0、running 被删除、空事件残留。数据库在仓库 `backend/.test-runtime/` 内临时建立，结束清理，不是 `/tmp` 或生产数据库。
- Flutter：`flutter test --no-pub ../backend/manual_tests/audit_playback_restore_test.dart --reporter expanded`，预期资产 7、实际 null；`audit_discovery_race_test.dart`，预期 `[90]`、实际 `[1,2]`。两项均以失败断言证明问题，非验收通过。
- R6：根虚拟环境内真实存储探针，输出 orphan_blob_count=1、orphan_bytes=3。
- 当前 Flutter Web 构建成功；未重跑整套 pytest/flutter test，先前测试数量不作为本报告正确性证据。所有 Flutter/Dart 执行均在沙盒外获准运行。
- 诊断脚本和截图放在被忽略的 `backend/manual_tests/`，不是正式验收资产。检查脚本曾因默认 outbox 路径创建根目录空数据库，确认没有表后已移至诊断目录；随后将 outbox 也定向至诊断数据库并重新执行。

## 建议处理顺序

1. 先修 R1、R2、R3，恢复安全边界和主能力；不同时扩展新功能。
2. 修复 R4–R8，以真实状态转换回归保护。
3. 收敛两套播放执行、任务呈现与有证据的模型样板；保留所需业务对象。每个领域单独审查/提交。
4. 把“已实现”与“已验收”文档分开纠正，用少量完整用户流程替代重复 mock 和字符串测试。
5. 按领域把 U1–U12 的设计关闭条件纳入同一次交付验收；先做信息结构和共享组件的减法，再调视觉细节，不用全面视觉重写代替整改。

不建议现在许诺“必须删除几万行”。可删数量应来自具体重复路径和失效兼容的清单，而不是新的行数指标。
