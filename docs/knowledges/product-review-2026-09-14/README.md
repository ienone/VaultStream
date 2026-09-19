# 产品与架构整体重审：证据与验证

2026-09-13 开始调查，2026-09-14 汇总。本文保留判定依据，不另立产品方案；结论与实施次序见[整体改进方案](../../plans/2026-09-14-product-architecture-review.plan.md)，目标体验与语义分别回到已修订的[前端原方案](../../plans/2026-06-10-frontend-information-architecture-redesign.plan.md)和[系统构想](../../plans/2026-07-15-vaultstream-system-concept.plan.md)。

下文是审查时的代码与运行快照，不作为当前实现清单。三个失败探针对应的 P0 缺口已完成本地修复，后续状态以[持续处理问题](../../issues/2026-09-14-continuous-processing-integrity.md)和[实施进度](../../plans/2026-09-14-product-architecture-review.process.md)为准；当前前后端契约见各模块文档。

## 基线与证据强度

- 代码基线：[b98815ba](https://github.com/ienone/VaultStream/commit/b98815ba1842414f43036d58bb27bb8359d84ade) 加审查时已有的未提交变更，含五平台收藏、会话刷新、TG 媒体/增量与自动聚合；不当作已发布版本。本轮未修改这些业务代码，也未撤销已有文档整理和截图删除。
- 产品背景先读两份原计划与[UI 审校](../ui-review-2026-09-13/README.md)，再核对领域文档、API/schema、实际调用链、近期进展与历史验收后段。原文的“已完成/未完成”不直接继承。
- 新界面观察使用 9 月 13 日已有 Flutter Web release 构建、隔离的当前 FastAPI、复制的合成 SQLite 和本地样例媒体。正常桌面 1280×900、手机视口 390×844，不是原生手机或当前未提交前端的重新构建。
- 后端在独立临时数据库运行，无生产 worker、定时巡逻、登录保活、模型或推送。浏览器隔离上下文把 API 请求固定到该库的占位 token；这不验证正常鉴权配置/恢复。新取证仅允许本地请求及公开字体下载，不访问真实收藏来源。
- 正式回归、失败探针、真实平台历史记录、合成运行截图、设计概念图分别标识：截图不能证明模型执行，模型有效 JSON 不能证明语义正确，接口成功不能证明用户任务完成。

<a id="e1"></a>
## E1 · 现有导航切开了一个用户任务

[RootPageActions](../../../frontend/lib/layout/root_page_actions.dart#L24)在非 compact 显示搜索、Agent、消息、账号、设置五个图标；compact 将五项放入同一个 PopupMenu。手机搜索不是一触可达；“工具有入口”和“日常入口组织合理”是不同判断。

[AppShell](../../../frontend/lib/layout/app_shell.dart#L101-L205)和[路由](../../../frontend/lib/routing/app_router.dart#L180-L395)把动态/收藏库/自动化作为主分支；[动态页](../../../frontend/lib/features/dashboard/dashboard_page.dart#L162-L218)另用“事件变化”切换到更新排序。事件有详情路由，不等于有持续关注目标和新事实入口。

当前连续接入路径被分成：平台访问身份在 `/accounts/:platform`；收藏范围/调度在 `/automation/sync`；RSS/TG 来源在 `/settings?tab=sources`；结果在动态/收藏库。组合成“来源与账号”工作区的理由是减少一次连接的往返，不是把来源与凭据合并为一张表。

<a id="e2"></a>
## E2 · 已有体验基础应保留，平行任务状态应收敛

| 证据 | 当前事实 | 对设计的约束 |
| --- | --- | --- |
| [ResponsiveLayout](../../../frontend/lib/core/layout/responsive_layout.dart)、[SettingsPage](../../../frontend/lib/features/settings/settings_page.dart#L31-L75) | 统一空间类别、局部约束与支持 pane 判断已实现 | 不再立项“新建断点系统”；手机单列、桌面辅助区按有效内容决定 |
| [SettingGroup/Tile](../../../frontend/lib/features/settings/presentation/widgets/setting_components.dart) | 连续行、尾部值/开关、局部展开编辑已存在 | 业务迁出设置不等于重造所有设置控件 |
| [Collection 查询状态](../../../frontend/lib/features/collection/collection_page.dart#L122-L158)、[局部搜索入口](../../../frontend/lib/features/collection/collection_page.dart#L281-L310)与[全局搜索](../../frontend/pages/search.md) | 收藏库与全局搜索有不同输入/范围及容器 | 建议一个上下文搜索；保留普通结果，不把合并搜索误作自动聊天 |
| [当前导航](../../frontend/navigation.md)、[媒体会话](../../frontend/components/media-rendering.md) | 标准返回、隐藏分支隔离、图片选择、PDF 页码和播放器状态已有专门处理 | 重组入口时保留语义 ID、草稿、返回来源与阅读/播放位置 |

<a id="e3"></a>
## E3 · 页面、动效和设计参考

### 原审校的有效视觉证据

本轮复看[逐页分析](../ui-review-2026-09-13/pages.md)及其图组，重点判断跨页关系，而非沿用原整改排序：

| 图组/过程 | 本轮判断 |
| --- | --- |
| [04 动态](../ui-review-2026-09-13/assets/04-comparison.png)、[06 收藏](../ui-review-2026-09-13/assets/06-comparison.png) | 已有真实信息流与窄屏单列，不应按旧文档重新做迁移占位；候选决策与已保留材料仍需明确区分 |
| [16 自动化](../ui-review-2026-09-13/assets/16-comparison.png)、[17 同步](../ui-review-2026-09-13/assets/17-comparison.png) | 阶段入口适合诊断，但“去哪查看有用结果/如何持续追踪”不能只靠这些后台页解决 |
| [25 设置](../ui-review-2026-09-13/assets/25-comparison.png)、[28 来源](../ui-review-2026-09-13/assets/28-comparison.png) | 连续设置行可复用；来源是业务对象，不只是低频偏好；账号/来源/同步应形成一个用户任务 |
| [42 事件](../ui-review-2026-09-13/assets/42-comparison.png) | 成员和关系有真实维护界面，但关注意图、实质变化、综合/原始证据层次仍需增补 |
| [设置展开录像](../ui-review-2026-09-13/assets/motion/settings-expand.webm)、[内容进入/返回录像](../ui-review-2026-09-13/assets/motion/detail-navigation.webm) | 局部展开让后续条目让位；阅读进入/返回保持对象归属。保留标准机制，不统一成整页表演式动画 |

![原审校：动态与事件视图的当前组织](../ui-review-2026-09-13/assets/04-comparison.png)

![原审校：来源配置在设置工作区中](../ui-review-2026-09-13/assets/28-comparison.png)

图组内数据是合成样例；十类模板截图不证明十类来源生产链完成。只有首屏、内容少或滚动到某位置不能认定裁切或布局浪费。原动效记录没有帧率测量，本轮也不声称全端流畅。

### 本轮运行复核

操作顺序为桌面动态 → 点击设置 → 信息来源；随后重新载入手机首页 → 打开工具菜单。实际读取 discovery/items、settings、discovery/sources 与 notifications，内容来自隔离库；没有提交来源配置、执行登录/同步或外发。

| 状态 | 观察重点 | 证据 |
| --- | --- | --- |
| 桌面首页 `/home` | 三个主目的地、独立候选卡与共享工具区 | [运行截图](assets/home-desktop.png) |
| 桌面来源 `/settings?tab=sources` | 来源对象位于设置分区、连续行和保留策略 | [运行截图](assets/sources-desktop.png) |
| 手机首页 `/home` | 单列候选卡、底栏、页头保存/工具入口 | [运行截图](assets/home-mobile.png) |
| 手机工具展开 | 搜索、Agent、消息、账号、设置同在一菜单 | [运行截图](assets/tools-mobile.png) |

运行中返回按钮曾被 Flutter 语义层拦截，按文本等待菜单项也未定位成功；最终重新载入首页并按实际 menuitem 语义观察。没有据此判定产品返回失效，也没有将账号跳转、菜单键盘操作或登录记为新验收通过。首次全禁外网截图缺少中文字形，不用于最终视觉结论；仅允许公开字体请求后重拍。

### 结构概念图，不是实现或验收证据

- [两种布局比较](assets/navigation-concepts.png)：用于比较“关注成为主目的地”和“继续把自动化置顶”的取舍。
- [建议结构](assets/recommended-navigation.png)：桌面分组导航、手机三目的地与工作区入口。已检查图中文字层级与入口归属。

![生成的目标结构参考：非运行界面](assets/recommended-navigation.png)

这不是像素规范：手机卡片内来源与 AI 说明过密，默认应折叠；保存按钮占位不能照搬为遮挡卡片，必须给持续动作/播放器留出真实布局空间；工作区打开需明确遮罩、焦点和关闭行为。图中跨城市材料是占位，不可据此自动合并事件。准确交互以[前端方案](../../plans/2026-06-10-frontend-information-architecture-redesign.plan.md)为准。

<a id="e4"></a>
## E4 · 捕获、登录、收藏和订阅已有实际链路

| 调用链 | 能证明什么 | 不能证明什么 |
| --- | --- | --- |
| [捕获控制器](../../../frontend/lib/features/collection/providers/content_actions_controller.dart) → [ContentService](../../../backend/app/services/content_service.py) → [解析任务](../../../backend/app/tasks/parsing.py) → 内容详情 | 捕获/导入不是仅保存一个 URL；原文、媒体、人工字段候选及来源有实际消费者 | 所有平台解析质量、硬中断接续和所有附件入口完整 |
| [收藏 UI/provider](../../../frontend/lib/features/settings/providers/favorites_sync_provider.dart) → [FavoritesSyncService](../../../backend/app/services/favorites_sync_service.py) → [FavoritesSyncTask](../../../backend/app/tasks/favorites_sync.py) → [五平台能力与 Fetcher 注册](../../../backend/app/adapters/favorites/__init__.py) → ContentService | 知乎、小红书、Bilibili、微博、X 不再是未接通占位；分页、集合身份、幂等来源和失败不推进已有实现 | 所有集合/大库到尾、上游重排/新增/移除时完整覆盖。预览成功不等于持续导入成功 |
| [BrowserAuthService](../../../backend/app/services/browser_auth_service.py) → QR driver 或 Cookie 保存 → [ConfigService 条件刷新](../../../backend/app/services/config_service.py#L203-L228) → Adapter | 凭据持久化/重新登录/退出竞争有保护；X 使用显式 Cookie 网页会话，不能要求其伪造统一扫码能力 | 登录永不过期、每个访问 scope 都有效、静态加密已完成 |
| [DiscoverySyncTask](../../../backend/app/tasks/discovery_sync.py) → [RSS](../../../backend/app/adapters/discovery/rss.py)/[TG](../../../backend/app/adapters/discovery/telegram.py) → 内容关联/媒体/动态 | RSS、TG 不是只有来源表单；TG 新实现有增量跨页、媒体与相册处理 | RSS 输入总是全文；正文更新能被完整重新理解；游标推进后所有后处理可恢复 |

近期[来源处理进展](../../plans/2026-09-13-source-processing-delivery.process.md)记录微博/X 两批各两条无重叠、Bilibili 本人收藏及集合、知乎/小红书小批读取、TG 跨页与隔离入库；本轮没有重复真实平台请求。代码和证据支持“部分实现且多条链路已接通”，不支持“五平台长期全量同步完成”。

去重保留上下文还没有完整到达普通阅读页面：[ContentDetail](../../../backend/app/schemas/content.py#L129-L194)有单一 `source` 与内容数据，但不返回 ContentSource 历史列表；收藏导入的集合记录不应只能留在数据库/任务结果中。发现候选已有独立来源关联输出，不能错误声称全系统完全没有来源展示。

<a id="e5"></a>
## E5 · 媒体、文档与 Agent 的旧负面结论已过时

- **视频生产链：** [read_video_media/transcript_chunks](../../../backend/app/adapters/bilibili_parser/video_media.py#L13-L116)读取 Bilibili 章节与字幕，带稳定媒体身份、时间区间和平台生成标记；解析绑定资产后供详情、搜索与播放器使用。已有真实视频浏览器播放、章节 seek 和 Agent 时间点引用点击记录，不能再写“解析器不生产任何时间字段”。也不能从一个 Bilibili 样本外推任意音视频 ASR。
- **PDF 生产链：** [extract_content_documents](../../../backend/app/services/document_text.py#L130-L181)验证当前原件/内容版本，按文件与页写入原生文本并撤销旧索引；[DocumentReader](../../../frontend/lib/features/collection/widgets/detail/document_reader.dart)与[原页预览](../../../frontend/lib/features/collection/widgets/detail/document_pdf_preview.dart)消费同一文件/页状态。扫描无文本有明确限制，不等于 OCR。
- **搜索 → 使用：** [UnifiedSearchService](../../../backend/app/services/search_service.py) → [search_content](../../../backend/app/services/agent/tools/search.py) / [read_content](../../../backend/app/services/agent/tools/reading.py) / [read_image](../../../backend/app/services/agent/tools/vision.py) → [Agent 会话](../../../backend/app/services/agent/service.py) → [前端引用](../../frontend/pages/agent.md)。真实验收记录有长文末段召回、原文引用、图片读取、PDF 指定页回答与可点击路由，不是纯聊天壳；尚无证据支持开放式问题普遍高质量。
- **检索规模边界：** [向量扫描](../../../backend/app/services/embedding_service.py#L819-L848)先按 indexed_at 降序截取行，再计算相似度；[默认配置](../../../backend/app/core/config.py#L97)上限 5000，是索引行不是内容篇数。旧材料可能被截断；FTS 仍可命中，不代表语义覆盖完整。人物/主题是字段聚合，不是知识图谱实体。

历史实证集中在[真实场景验收](../../issues/2026-09-10-real-world-acceptance.md)的“真实 PDF 摘要与 Agent 页码回答”“视频原文时间点引用真实点击与播放”“Android 真实 PDF 系统分享”“混合系统分享”等后段。后续[UI/原生续接](../../plans/2026-09-12-ui-motion-continuation.process.md)补充 Android MediaSession、后台/PiP 与 PDF 交互；短媒体模拟器证据不是长时真机验收。

<a id="e6"></a>
## E6 · 同步成功和耐久后处理并非同一件事

[DiscoverySyncTask](../../../backend/app/tasks/discovery_sync.py#L234-L391)在循环中用内存 `post_ingest_work` 暂存下一阶段；内容、关联和 source cursor 在 362 行附近提交，其后才做媒体归档与 hooks。若提交后中断，源进度可先于后处理完成。重复项可能补摘要/索引，但明确 `distribution=False`，不能把重复扫描当作所有阶段的恢复机制。

[PostIngestService](../../../backend/app/services/post_ingest.py#L17-L136)依次处理摘要、索引、评分和分发；摘要/自动审批异常记录后被隔离，索引先 `asyncio.create_task`，在异步函数内部才创建 run。TaskRun 记录存在不代表创建前或结束后的阶段一定会被接续；日志中的“hooks completed”也不是每阶段均已成功。

[发现轮询](../../../backend/app/tasks/discovery_sync.py#L74-L96)等待来源检查后再等待自动聚合。模型最慢可等待 90 秒且来源处理也串行影响轮询；因此建议调度只创建 due 工作，聚合与来源执行独立领取，而非另装通用工作流框架。

<a id="e7"></a>
## E7 · 三个失败探针，采用真实数据库实现

临时 pytest 使用[现有 fixture](../../../backend/tests/conftest.py)：独立 SQLite、正式 ORM/队列、默认无 worker 与外部网络。重建服务对象模拟进程留下的数据库状态，不在用户运行进程上做强杀/重放实验。

| 独立预期 | 构造 | 实际结果 |
| --- | --- | --- |
| 遗留解析应能接续/归类 | 一天前 RUNNING Task；新 TaskQueue.dequeue | 返回 None，预期断言失败 |
| 超时发送中状态不能永久悬挂 | 可用目标的 PROCESSING，过期锁及 dead-worker；新 worker._claim_items | 空领取且仍 PROCESSING，预期断言失败 |
| 事件成员证据不受候选 TTL 独立删除 | 两个过期 VISIBLE SOURCE + 一个 REPORT；真实 hard_delete 清理 | 只剩 report 关系，预期断言失败 |

审查时临时运行结果为 **3 failed**；没有把失败视为通过或削弱断言。临时脚本已删除，后续修复及保留回归见[持续处理完整性问题](../../issues/2026-09-14-continuous-processing-integrity.md)，本文只保留修复前复现。

<a id="e8"></a>
## E8 · 后端收敛要按真实调用者，不按名字删复杂代码

| 当前代码证据 | 判断与建议 |
| --- | --- |
| [WeiboSession](../../../backend/app/adapters/weibo_session.py#L29-L85)、[X transport](../../../backend/app/adapters/twitter_web.py#L16-L80)、[Cookie 更新](../../../backend/app/services/config_service.py#L215-L228) | Adapter/transport 直接取配置，部分会话自己持久化；配置层又调用 Adapter 解析 Cookie。将持久化/CAS 放账号边界，协议与会话快照注入平台实现；不是抹平每个平台的协议差异 |
| [X 健康检查](../../../backend/app/services/browser_auth_service.py#L105-L118) | 调用收藏 Fetcher 私有 `_read_page`，登录状态与书签实现相互依赖。抽成共享平台能力探测，保留“真正读到受保护资源”的语义，不改成网页 200 判断 |
| [distribution/scheduler](../../../backend/app/services/distribution/scheduler.py#L11-L47) | 是有调用者的入队/独立 session 包装，不是废弃第二调度器；耐久交接时替换 background wrapper，不机械整删 |
| [ContentDistributor](../../../backend/app/tasks/distributor.py#L131-L162)、[worker 调用](../../../backend/app/tasks/distribution_worker.py#L588-L595) | 当前主要提供 payload/media rendering，命名与归属过时但逻辑仍有效；迁入渲染模块的公开接口 |
| [分发规则 service](../../../backend/app/services/distribution_rule_service.py)、[DistributionService](../../../backend/app/services/distribution/service.py)、[decision](../../../backend/app/services/distribution/decision.py) | CRUD、匹配、入队/策略各有不同消费者，不把同领域多个 service 一律判重复 |
| [Agent push](../../../backend/app/services/agent/tools/push.py#L49-L91)、[rules](../../../backend/app/services/agent/tools/rules.py#L77-L80)、[api_bridge](../../../backend/app/services/agent/tools/api_bridge.py#L186-L228) | 前两者复用业务服务；bridge 有白名单并重入正式 ASGI，不是复制全部业务。只收窄有真实重复的写入口，保留有用读取与策略边界 |

本轮另外确认 `cli_unavailable` 仅残留在[FavoritesSyncService](../../../backend/app/services/favorites_sync_service.py#L137-L139)和[PlatformHealthService](../../../backend/app/services/platform_health_service.py#L193)的可用性分类，X 已改为网页传输。应按当前结构化错误 contract 清理旧 CLI 分类并正确表达 browser_unavailable，避免凭旧条件继续把运行环境故障当“能力可用”。

<a id="e9"></a>
## E9 · 自动聚合、安全与模型调用的实际边界

[ContentAggregationService](../../../backend/app/services/content_aggregation_service.py#L41-L142)有开关、每小时节奏、首轮 24 小时窗口、模型 schema、有效引句检查、迟到策略复查；[repository](../../../backend/app/repositories/content_aggregation_repository.py#L57-L179)有版本门禁、结果与游标同事务保存。近期真实模型记录包含续接及完整隔离落库，不能再称“只有接口”或“没有模型”。

但 `20 新 + 10 上下文` 并非全库事件检索：旧事件通过已入选来源的成员关系找回，context 再以关联优先/近七天补充；仅用一条全新报道无法保证召回很久以前的相关事件。事件人工编辑使 `event_updated_at` 不再匹配，整个自动候选被排除；这是保护人工结果的有效但过粗的方式，建议细化而非删除保护。

生成后只发布事件并可选入分发，没有调用统一索引 hooks；发布/分发在提交之后，也不与产物保存形成同一耐久交接。生成成功可以是真的，同时索引/通知/送达仍不完整。模型输出引句存在只证明文本可定位，不证明引句支持每个推论。

[ConfigService.set_value](../../../backend/app/services/config_service.py#L166-L190) → [SystemRepository.upsert_setting](../../../backend/app/repositories/system_repository.py#L26-L36)直接保存配置 JSON，Cookie 刷新复用此体系；代码没有静态加密边界。SecretStr、遮蔽输入与日志脱敏有价值，但不能当加密存储。密钥、轮换和备份恢复方案需另行确认后实施。

[LLMFactory](../../../backend/app/core/llm_factory.py#L49-L104)存在 Agent → Text → Vision 的隐式回退；同文件兼容类的 browser-use 说明与当前依赖/调用现状不一致。建议先显式化角色和数据去向，核对现用 SDK 后再移除无实际需要的补丁；不因注释陈旧就猜测当前供应商适配都可删除。摘要、聚合、视觉和索引需要共同的最小调用记录，但不需要通用工作流框架。

<a id="e10"></a>
## E10 · Animeko：借鉴组织逻辑，不复制业务菜单

上游固定版本为 [open-ani/animeko](https://github.com/open-ani/animeko/tree/7e20fdc8e1580bd2db65cdd57e87a1c0d4f6c9d6)，以下链接均为核对过的永久源码定位，不以参考截图猜实现。

| 上游依据 | 能借鉴的机制 | VaultStream 的不同约束 |
| --- | --- | --- |
| [NavRoutes：三个主页面](https://github.com/open-ani/animeko/blob/7e20fdc8e1580bd2db65cdd57e87a1c0d4f6c9d6/app/shared/app-platform/src/commonMain/kotlin/navigation/NavRoutes.kt#L128-L139)、[MainScreen：主导航/搜索/设置](https://github.com/open-ani/animeko/blob/7e20fdc8e1580bd2db65cdd57e87a1c0d4f6c9d6/app/shared/src/commonMain/kotlin/ui/main/MainScreen.kt#L235-L301) | 主目的地围绕探索、收藏与消费，搜索和设置是工具层 | 不照搬 CacheManagement 主导航；本产品持续关注是结果空间，后台阶段不是日常目的地 |
| [SearchPage：布局判断](https://github.com/open-ani/animeko/blob/7e20fdc8e1580bd2db65cdd57e87a1c0d4f6c9d6/app/shared/ui-exploration/src/commonMain/kotlin/ui/exploration/search/SearchPage.kt#L108-L128)、[选择与滚动](https://github.com/open-ani/animeko/blob/7e20fdc8e1580bd2db65cdd57e87a1c0d4f6c9d6/app/shared/ui-exploration/src/commonMain/kotlin/ui/exploration/search/SearchPage.kt#L179-L215) | 同一个 selectedItemIndex、navigator、gridState 跨单/双栏使用，变化的是容器 | 收藏、事件、搜索和阅读保留对象身份；不是单独做两个页面靠刷新同步 |
| [SettingsScreen：共享导航状态](https://github.com/open-ani/animeko/blob/7e20fdc8e1580bd2db65cdd57e87a1c0d4f6c9d6/app/shared/ui-settings/src/commonMain/kotlin/ui/settings/SettingsScreen.kt#L197-L229)、[列表与详情容器](https://github.com/open-ani/animeko/blob/7e20fdc8e1580bd2db65cdd57e87a1c0d4f6c9d6/app/shared/ui-settings/src/commonMain/kotlin/ui/settings/SettingsScreen.kt#L521-L592) | 选择状态驱动列表与详情，而非按屏幕重新创建业务状态 | 复用 VaultStream 已有设置返回机制；来源迁出属于职责调整，不是再造 pane 框架 |
| [AutoSelectExtension](https://github.com/open-ani/animeko/blob/7e20fdc8e1580bd2db65cdd57e87a1c0d4f6c9d6/app/shared/app-data/src/commonMain/kotlin/domain/player/extension/AutoSelectExtension.kt#L24-L39)、[MediaSelectorSummaryBanner](https://github.com/open-ani/animeko/blob/7e20fdc8e1580bd2db65cdd57e87a1c0d4f6c9d6/app/shared/ui-mediaselect/src/commonMain/kotlin/ui/mediaselect/summary/MediaSelectorSummaryBanner.kt#L50-L161) | 自动选源融入当前会话，局部呈现自动查询/人工选择/已选结果；用户随时替换 | 自动关联/整理也应在材料旁可解释、可纠正；新闻不同来源不是可互换的视频地址，不能因相似而删掉异议 |

借鉴到任务路径就是：连接一次后持续接入，从上次读/播的位置继续，自动判断有局部状态与人工覆盖，不要求用户去另一个后台页面才能理解结果。颜色、圆角和 hover 只是承载这些关系的形式。

## 原始审查阶段的验证边界

| 检查 | 结果与边界 |
| --- | --- |
| 根虚拟环境 `python -m pytest backend/tests -q -m "not integration"` | 当时 **160 passed**，但未覆盖 E7 的三个缺口；不是当前测试数量或功能完成率 |
| 三个针对中断/证据保留的临时探针 | 修复前 **3 failed**，复现见 E7；后续修复不改写原始观察 |
| 运行 UI | 合成数据的入口、来源分区与菜单操作；复用旧构建，不包括较新账号/聚合控制面的重新视觉验收 |
| 文档与素材 | 修改范围的本地链接、锚点、代码行号范围和引用图片解码检查通过；`git diff --check` 通过。这些检查不替代调用链与图像内容审查 |
| Flutter analyze/test/build | **本轮未运行**：仓库要求沙盒外提权，此会话没有提权执行通道；没有将旧记录写成本轮验证 |
| 外部平台/模型/发送 | 本轮无新增真实登录、收藏同步、私人材料模型请求或推送；近期实测仅引用其原记录并限制结论范围 |
| 临时验收收尾 | 本轮隔离服务已正常退出；临时 pytest、浏览器操作和服务脚本已移除，必要截图和结论保留在本文 |

本轮未提交、推送、部署或迁移数据库；设计方向是建议，不是已获得逐项批准。后续以[垂直实施切片](../../plans/2026-09-14-product-architecture-review.plan.md#sequence)为单位验证有用结果、失败恢复和正常手机/桌面体验，不设置截图、测试或覆盖率指标。
