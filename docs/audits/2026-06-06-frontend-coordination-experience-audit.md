# 前端体验与前后端协同审计

> 日期：2026-06-06  
> 范围：收藏库、内容详情、收件箱、自动化、设置、账号中心、后台任务和 AI 配置约束。  
> 方法：静态代码审计为主，读取前端 Flutter、后端 FastAPI 和现有 docs；本轮未运行 Flutter/Dart 命令，因本地环境要求这类命令提权执行。

> 当前实施边界：embedding/语义索引策略和 Agent 工具权限相关功能先暂缓实现。本审计保留这些问题作为架构风险记录，但近期实现顺序、验收清单和任务拆分不应把它们作为当前工作项。

## 总体判断

当前 VaultStream 的问题已经不是“功能太少”，而是“功能推进快于产品结构和前后端契约收敛”。应用已经有动态、收藏库、收件箱、自动化四个主入口，设置、Agent、账号中心也已经从主导航中移出；这比早期“五个底边项 + 未来继续加项”的方向更合理。

但从用户视角看，仍有几个高优先级问题会直接削弱可信度：

1. AI 自动化没有统一策略层。用户在设置中关闭某项自动能力后，后台其他链路仍可能以另一种名义调用 LLM 并写回摘要、评分或标签。
2. 前端控制面无法完整约束后端自动行为。除摘要/评分外，自动语义索引、分发队列 worker、Cookie 保活、发现/收藏同步手动覆盖、Agent API bridge 都存在类似问题。
3. 收藏卡片到详情页的 shared transition 仍是局部修复。代码已经把飞行动画改为卡片预览，但详情页的目标 Hero 仍是空白整页 surface，因此用户仍会感到“两个白板之间有动画”。
4. 复杂操作大量依赖弹窗和抽屉，移动端/竖屏下可用宽度不足，且多层弹窗让任务结果、失败原因和下一步动作不稳定。
5. 设置项和实际能力没有完全对齐。例如 AI 评分只有兴趣画像和阈值，没有全局开关；摘要开关只约束部分后处理链路，不约束发现巡逻评分写入的 summary。
6. 文案和信息架构仍有旧概念残留。主导航已经叫“收件箱/自动化”，但部分前端文案和内部页面仍按“探索/发现/审核”组织，容易让用户无法判断内容处于哪个阶段。

下面按问题域展开。

## P0: AI 自动化策略没有统一横切层

### 现状证据

`backend/app/services/post_ingest.py` 的 `PostIngestService.run_for_content()` 接收 `summary`、`embedding`、`patrol`、`distribution` 参数。`generate_summary()` 内部会读取 `enable_auto_summary`，关闭时跳过摘要生成。

这只约束了“post-ingest 的自动摘要”路径，不代表所有 AI 写回都受控。

`backend/app/services/content_summary_service.py` 的 `generate_summary_for_content()` 只读取摘要模型配置和 API key，不检查 `summary_config.enabled`。这对手动按钮可以合理，但需要明确成“手动动作可显式覆盖自动开关”，否则用户会误以为开关是总闸。

`backend/app/tasks/discovery_sync.py` 新增发现内容后会 `queue_post_ingest_work(content.id, summary=True, embedding=True, distribution=True)`，随后在 `post_ingest_work` 执行完后，如果 `ingested_count > 0`，会调用 `await pipeline.score_discovery(db)`。该巡逻评分没有用户可见的全局启停开关。

`backend/app/services/patrol_service.py` 的 `score_item()` 会把 LLM 输出写入：

- `content.ai_score`
- `content.ai_reason`
- `content.summary`
- `content.ai_tags`
- `content.discovery_state`

这意味着即使用户关闭了“自动摘要”，发现巡逻评分仍可能给内容写入一段 `summary`。从实现角度它是“评分时的一句摘要”，但从用户视角它仍是 AI 自动生成摘要。

`backend/app/schemas/discovery.py` 的 `DiscoverySettingsResponse/Update` 只有：

- `interest_profile`
- `score_threshold`
- `retention_days`

没有 `enable_ai_scoring`、`enable_discovery_patrol` 或类似字段。

`frontend/lib/features/settings/presentation/tabs/automation_tab.dart` 的“内容生成设置”只提供 `enable_auto_summary`；“AI 发现”区域提供兴趣画像、评分阈值和保留天数，但没有 AI 评分总开关。

`frontend/lib/features/discovery/providers/discovery_settings_provider.dart` 也只 PATCH `interest_profile`、`score_threshold`、`retention_days`。

### 用户影响

用户无法可靠回答：

- 关闭自动摘要后，哪些后台链路仍会调用 LLM？
- 关闭自动摘要后，发现内容为什么仍出现 AI 生成的一句 summary？
- 我能不能只保留发现源同步，但不让系统自动评分？
- 我能不能只生成摘要，不让发现巡逻自动改变可见/忽略状态？
- 手动点击“生成摘要”是否应该无视自动摘要开关？

这不是单个 UI 漏项，而是缺少全局 AI 策略契约。

### 建议设计

新增一个后端策略层，例如 `AutomationPolicyService` 或 `AIProcessingPolicy`，把“自动后台行为”和“手动显式行为”区分开：

- `enable_auto_summary`：只控制自动 post-ingest 摘要/RAG 分块。
- `enable_discovery_patrol` 或 `enable_ai_scoring`：控制发现/收件箱自动评分、自动写入 `ai_score/ai_reason/ai_tags/summary`、自动改变 `discovery_state`。
- `enable_auto_embedding`：如果未来需要减少成本或保护隐私，应提供语义索引自动入库开关；现在 embedding 是 post-ingest 默认调度，只靠 API key 是否存在兜底。
- `manual_override`：手动按钮、单条巡逻评分、手动摘要生成应在 API 层明确声明是用户显式动作，可以绕过“自动”开关，但 UI 必须展示当前动作会调用哪个模型、写回哪些字段。

后端所有后台入口都应先问策略层：

- 解析后处理。
- 发现源同步后处理。
- 收藏同步导入后处理。
- 单条重新解析后的后处理。
- 批量导入后的后处理。

前端设置页也应从“模型字段配置”升级为“能力策略 + 高级配置”：

- 内容理解：自动/手动/关闭。
- 发现评分：自动评分开关、阈值、兴趣画像。
- 语义索引：自动入库开关、重建入口。
- Agent：是否允许工具调用、哪些工具需要确认。

## P0: 前端控制面与后端自动行为的扩展扫描

本轮继续按同一标准扫描：只要后端会自动轮询、自动写回、自动触发外部请求、自动入队、自动删除或允许 Agent 代替用户触发，就必须能在前端控制面中被明确表达。当前存在多类不对齐。

### 1. 自动语义索引没有总开关

后端路径：

- `backend/app/services/post_ingest.py` 的 `run_for_content()` 默认 `embedding=True`，会调用 `schedule_embedding_index()`。
- `backend/app/tasks/parsing.py` 解析成功后调用 `PostIngestService().run_for_content(... embedding=True ...)`。
- `backend/app/services/content_service.py` 对已解析内容再次分享合并时，也会调用 `run_for_content(... embedding=True, distribution=True)`。
- `backend/app/tasks/discovery_sync.py` 对新发现内容和缺索引的既有内容会排入 embedding 后处理。
- `backend/app/services/embedding_service.py` 只检查 `embedding_api_key`、模型和维度，不存在 `enable_auto_embedding` 之类策略键。

前端现状：

- 设置页提供 Embedding API key、模型、维度、索引状态和手动重建。
- 没有“自动语义索引”开关，也没有“仅手动索引”模式。

影响：

- 用户配置了 key 后，后台解析、发现同步、收藏同步导入都可能自动产生远端 embedding 调用。
- 想降低费用、关闭外部向量化或临时暂停索引时，前端只能移除/改坏 key，这不是可靠产品控制。
- 处理状态面板里的“重建索引”是手动恢复入口，不是自动策略控制。

建议：

- 增加 `enable_auto_embedding`。
- 自动后处理必须检查该策略。
- 手动 `semantic_reindex` 可作为显式覆盖，但请求/运行记录中应标记 `trigger=manual` 和 `policy_override=true`。
- AI 能力状态中区分“语义搜索可用”和“自动索引开启”。

### 2. 发现源 enabled 只控制定时同步，不控制手动同步

后端路径：

- `DiscoverySyncTask._sync_due_sources()` 只扫描 `DiscoverySource.enabled == True` 的来源。
- 但 `backend/app/routers/discovery.py` 的 `POST /discovery/sources/{source_id}/sync` 只检查来源存在和 kind 支持，不检查 `source.enabled`。
- `DiscoverySyncTask.sync_source_by_id()` 也不检查 `source.enabled`，直接进入 `_sync_single_source()`。

前端现状：

- 自动化设置中有来源启用开关。
- 健康矩阵中部分同步按钮会根据 `source.enabled` 禁用，但 API 本身没有把 disabled 当作禁止同步。

影响：

- “禁用来源”实际语义是“不参与定时扫描”，不是“禁止该来源被同步”。
- 如果前端某处遗漏按钮禁用、Agent 调用 API、或未来新增入口，disabled 来源仍可被手动同步。
- 这可以是合理的“手动覆盖”，但必须显式：例如按钮写“临时同步已禁用来源”，API 要求 `force=true`。

建议：

- 明确拆分 `enabled_for_schedule` 和 `allow_manual_sync`，或保留 `enabled` 但手动接口默认拒绝 disabled，除非传 `force=true`。
- 运行记录中标记 `source_enabled_at_trigger`。
- 前端禁用来源后，所有同步入口应展示一致语义。

### 3. 收藏同步平台 enabled 只控制定时/全量范围，不控制单平台手动同步和 Agent 工具

后端路径：

- `FavoritesSyncTask._sync_loop()` 会读取 `favorites_sync_platforms` 并同步 enabled platforms。
- `sync_all_platforms_once()` 会在每个平台前重新读取 enabled list，能尽快响应运行时禁用。
- 但 `sync_platform_by_name(platform)` 不检查平台是否在 enabled list 中。
- `POST /favorites-sync/sync` 传入单平台时会直接调用 `sync_platform_by_name()`。
- Agent 工具 `import_favorites` 也直接调用 `sync_platform_by_name(platform)`。

前端现状：

- 自动化设置中每个平台有“启用同步”开关。
- 同一行仍有“手动同步”按钮，按钮只根据 `available == false` 禁用，不根据该平台是否 enabled 禁用。

影响：

- 用户关闭某平台同步后，仍可通过同一控制面手动同步该平台。
- 如果这个语义是“关闭自动同步但允许手动同步”，文案现在不够准确。
- 如果用户理解为“禁止该平台同步”，后端行为会违反预期。
- Agent 可以在用户确认后触发被禁用平台同步；没有更高层策略阻止。

建议：

- 文案改为“自动同步此平台”，而不是笼统“启用同步”。
- 手动同步 disabled 平台时要求二次确认或 `force=true`。
- Agent 工具调用前检查平台策略，或要求更高风险确认。
- 增加全局 `enable_favorites_sync_scheduler` 和可选 `allow_manual_favorites_sync_disabled_platform`。

### 4. 分发自动审批、规则刷新和队列 worker 缺少全局暂停

后端路径：

- `backend/app/main.py` 启动时总是启动 `DistributionQueueWorker`，worker 每 5 秒领取到期队列项。
- `ContentParser._check_auto_approval()` 在解析完成后调用 `PostIngestService().auto_approve_and_enqueue()`。
- `DistributionService.auto_approve_if_eligible()` 会根据 enabled rules 自动把内容设为 `AUTO_APPROVED` 并入队。
- `ContentService.create_share()` 对已解析内容再次分享合并时会 `run_for_content(... distribution=True)`。
- `POST /distribution-rules`、`PATCH /distribution-rules/{id}`、`DELETE /distribution-rules/{id}` 都会调用 `refresh_queue_by_rules()`，可能批量改变既有内容审批状态并入队。
- `POST /distribution/trigger-run` 会扫描最多 100 条已审批内容并入队。

前端现状：

- 有规则启用开关、规则的“人工审批”开关、目标启用开关、BotChat 启用开关、队列项取消/重试/排期。
- 没有“暂停所有自动分发”“只入队不推送”“暂停 worker”“规则变更不自动刷新既有内容”的总策略。

影响：

- 规则开启、关闭或审批策略修改会产生级联副作用，可能影响历史内容，而前端 dialog 只是“保存修改”。
- 用户无法在维护窗口暂停所有外部推送。
- 一旦队列项已经 scheduled，worker 会继续推送，除非逐项取消或禁用目标/群组。
- 这是外部副作用链路，应按 P0 处理。

建议：

- 增加 `distribution_mode`: `paused / manual_queue_only / auto_queue / auto_push`。
- worker 领取队列前检查全局推送策略。
- 规则更新接口支持 `refresh_existing=false` 或 dry-run preview。
- 前端保存规则时展示“会影响既有内容/会新增队列项/会自动推送”的数量预估。
- 动态页/自动化页提供全局暂停按钮和暂停状态。

### 5. Cookie 保活任务没有前端控制面

后端路径：

- `backend/app/main.py` 获得 leader 后启动 `CookieKeepAliveTask`。
- `backend/app/tasks/maintenance.py` 会启动知乎、小红书、微博三个保活循环。
- 这些循环会周期性调用 `browser_auth_service.refresh_zhihu_zse_cookie()` 或 `check_platform_status()`。
- 随机间隔是代码常量，前端没有开关、频率、平台级控制。

前端现状：

- 连接与账号页/账号中心可以登录、检测、登出。
- 没有“自动保活 Cookie”总开关，也没有平台级保活开关。

影响：

- 用户登录平台后，后端可能在后台周期性触达平台或刷新指纹。
- 对隐私、风控、代理和账号安全敏感的用户无法关闭。
- 与收藏同步不同，保活不是显式同步行为，前端更需要说明。

建议：

- 增加 `enable_cookie_keepalive` 和 `cookie_keepalive_platforms`。
- 账号中心逐平台展示“自动保活：开启/关闭/最近执行/最近失败”。
- 手动登录检测与自动保活分开记录。

### 6. Agent 工具权限只有单次确认，没有用户级策略

后端路径：

- `AgentToolSpec.requires_confirmation` 对 `write/external_side_effect/dangerous` 工具要求确认。
- `api_bridge.py` 允许 Agent 访问受控 API 前缀，包括 `/api/v1/settings`、`/api/v1/favorites-sync`、`/api/v1/distribution-queue`、`/api/v1/bot-config`、`/api/v1/discovery` 等。
- `api_mutation` 的 permission level 是 `dangerous`，确认后可调用 allowlist 内的写接口。
- `import_favorites`、`push_batch`、`create_rule` 等专用工具也能触发外部副作用或写入系统。

前端现状：

- Agent 页面能展示确认卡并让用户批准/拒绝。
- 设置页没有工具 allow/deny、权限级别禁用、最大批量范围、禁止 Agent 修改设置、禁止 Agent 触发外部同步/推送等策略。

影响：

- 单次确认能防误操作，但无法表达长期偏好：例如“Agent 只能读库，不能改设置/触发同步/推送”。
- Agent 可以通过 API bridge 触发和普通前端同等的后端行为，绕过某些前端按钮级限制。
- 如果后端自动行为本身缺少全局策略，Agent 会放大这个问题。

建议：

- 增加 `agent_mode`: `read_only / confirm_write / disabled_external_side_effects / full_with_confirmation`。
- 增加 tool-level allowlist/denylist 设置。
- `api_mutation` 进一步拆分 settings、sync、distribution、bot、content 等 permission scope。
- Agent API bridge 调用 mutation 前先检查全局自动化策略。

### 7. 媒体归档设置控制面不完整

后端路径：

- `ConfigService.get_archive_media_config()` 读取 `enable_archive_media_processing`、`archive_image_webp_quality`、`archive_image_max_count`、`archive_video_max_count`。
- `ContentParser._maybe_process_private_archive_media()` 在解析时处理图片和视频。
- `ContentParser._handle_archived_media_fix()` 对已解析但未归档的内容补处理归档媒体。
- `DiscoverySyncTask._archive_discovery_media()` 对新发现内容归档图片。

前端现状：

- 系统设置只有“启用媒体压缩处理”、WebP 质量、单帖最大图片数限制。
- 没有视频数量/体积控制。
- 文案偏向“图片 WebP 压缩”，但后端 toggle 实际控制整个 archive media processing，包括发现图片归档和私有归档视频处理。

影响：

- 用户以为只是在控制图片压缩，实际也在控制更广义的媒体归档处理。
- 视频归档若开启，缺少前端体积/数量/网络成本控制。
- 已解析内容在再次进入 parse worker 的 skip/fix 路径时也可能补处理媒体；这受开关控制，但前端文案没有覆盖。

建议：

- 文案改为“自动归档远程媒体”。
- 图片压缩、图片数量、视频归档、视频数量/体积拆成独立策略。
- 内容详情处理状态中展示媒体归档是否启用及最近处理结果。

### 8. 发现清理会硬删除过期/忽略项，但策略不够可见

后端路径：

- `DiscoveryCleanupTask` 启动后每 6 小时运行。
- 它会把过期 visible 内容标记为 expired，并硬删除 `EXPIRED` 和 `IGNORED` 且 `expire_at < now` 的内容，同时删除相关 embedding、queue item、source、pushed record 链接。
- `discovery_retention_days` 在 `DiscoverySyncTask` 新建内容时写入 `expire_at`。

前端现状：

- AI 发现设置里有“发现保留天数”。
- 这个设置看起来像展示保留期，但没有强调会硬删除忽略/过期候选。
- 修改 retention days 不会自动重写既有内容的 `expire_at`。

影响：

- 用户可能不知道“忽略内容”会在过期后从本地库硬删除。
- 想保留历史候选或审计痕迹时，没有“归档而非删除”策略。
- 修改保留天数对已有候选的作用范围不清晰。

建议：

- 文案改为“候选保留与清理策略”。
- 增加 `discovery_cleanup_mode`: `hard_delete / expire_only / archive`。
- 前端显示“对新候选生效”或提供“应用到现有候选”的显式操作。

### 9. 解析 worker 和队列没有用户级暂停/成本控制

后端路径：

- `main.py` 按 `parse_worker_count` 启动解析 worker。
- `ContentService.create_share()` 新增内容后直接入解析队列。
- 批量收藏同步、Agent import、分享入口都可能批量创建内容并触发解析。

前端现状：

- 添加内容、收藏同步、Agent 工具都能触发解析。
- 没有“暂停解析队列”“仅入库不解析”“批量导入后手动解析”的模式。

影响：

- 大批量导入时可能立即触发大量平台请求、媒体归档、摘要、embedding、分发链路。
- 用户无法在配置未完成、网络/代理异常或外部平台风险较高时暂停解析。

建议：

- 增加 `ingest_mode`: `save_only / parse_only / parse_and_post_ingest`。
- 收藏同步和 Agent import 支持导入为收件箱候选，用户确认后再解析。
- 动态页提供解析队列暂停/恢复和积压数。

## 控制语义分类

当前不对齐不是同一种 bug，建议按以下四类修：

| 类别 | 当前例子 | 风险 | 处理方式 |
| --- | --- | --- | --- |
| 完全没有控制面 | Cookie 保活、自动 embedding、分发 worker 总暂停、Agent 工具策略 | 高 | 增加后端策略键和前端总控 |
| 只有局部控制 | `enable_auto_summary` 只管 post-ingest；媒体开关只按宽泛口径控制 | 高 | 拆分语义，所有入口统一读取策略 |
| 手动覆盖语义不清 | disabled 发现源/收藏平台仍可手动同步 | 中高 | API 加 `force=true`，前端显式提示 |
| 级联副作用不可预估 | 规则更新刷新既有内容、backfill、trigger-run | 高 | dry-run/preview、确认页、全局暂停 |

建议建立一个统一的 `AutomationPolicyService`，不要继续让各任务各自读取散落的 `system_settings` key。所有后台入口都应返回同一类 `policy_decision`：

- `allowed`: 是否允许。
- `reason`: 允许/拒绝原因。
- `requires_manual_override`: 是否需要显式手动覆盖。
- `estimated_side_effects`: 预估远端调用、写回字段、入队数量、可能推送目标。
- `policy_snapshot`: 运行时策略快照，写入 run metadata。

## P0: 收藏卡片到详情页转场仍是部分修复

### 现状证据

当前代码已经比旧实现更进一步：

- `frontend/lib/features/collection/widgets/list/collection_card_preview.dart` 定义 `collectionCardHeroTag(int contentId) => 'card-shell-$contentId'`，并抽出了 `CollectionCardPreview`。
- `frontend/lib/features/collection/widgets/list/content_card.dart` 用 `Hero(tag: collectionCardHeroTag(...), flightShuttleBuilder: collectionCardFlightShuttleBuilder(...))` 包住卡片预览。
- `frontend/lib/features/collection/content_detail_page.dart` 的 loading 状态会在有 `preview` 时显示同一 `Hero` 和 `CollectionCardPreview`。
- `frontend/lib/routing/app_router.dart` 已把详情页路由转场弱化为接近不透明的 fade。

这些是有效改进，但 loaded detail 状态仍存在核心问题。`ContentDetailPage` 数据加载成功后，详情页根部 Hero 的 child 是：

```dart
Material(
  color: colorScheme.surface,
  child: const SizedBox.expand(),
)
```

也就是说，目标 Hero 仍是一块整页空白 surface。`flightShuttleBuilder` 可以让飞行层看起来像卡片，但目标落点不是详情首屏中的真实卡片头部、封面、标题或内容结构。用户会看到“飞行时有卡片，落地后切成白板/页面”，这就是“有动画但像自欺欺人”的原因。

本轮已同步更新 `docs/known-issues/collection-card-detail-transition.md`，避免继续用旧的 `card-bg-*` 描述作为主要现状。

### 用户影响

- 前进时，卡片身份没有真正延续到详情首屏。
- 返回时，如果列表状态变化、SSE 刷新、筛选变化或图片缓存延迟，仍可能出现空白回落。
- 视觉上像页面切换叠了一个飞行动画，而不是卡片展开为详情。

### 建议设计

不要让详情页目标 Hero 是空白整页 surface。改成“详情首屏可见结构的一部分”：

1. 详情页顶部建立稳定的 `DetailHeroHeader`，包含封面/作者/标题/平台/标签等能与卡片对应的元素。
2. `card-shell-{id}` 的目标 Hero 应包住这个 header 的背景和关键内容，而不是 `SizedBox.expand()`。
3. 数据未加载时保留 `CollectionCardPreview`；数据加载完成后先落在 `DetailHeroHeader`，再 crossfade/expand 到完整详情布局。
4. 对不同内容类型建立最低一致性：文章、图集、视频、纯文本都至少有 title/author/platform/cover fallback 的目标区域。
5. 验收以 widget、route 和布局约束测试为主，覆盖桌面、手机竖屏、慢加载、返回和 SSE 刷新后返回等逻辑路径；人工视觉检查只作为补充。

## P0/P1: 移动端弹窗可用宽度不足，复杂任务不应继续塞进弹窗

### 现状证据

前端有大量 `showDialog`、`AlertDialog`、`Dialog`：

- `frontend/lib/features/collection/widgets/dialogs/filter_dialog.dart` 使用 `Dialog`，内部 `BoxConstraints(maxWidth: 500, maxHeight: 700)`，日期选择区域还有 `maxWidth: 400, maxHeight: 560`。
- `frontend/lib/features/review/widgets/distribution_rule_dialog.dart` 使用 `Dialog`，内部 `BoxConstraints(maxWidth: 560)`，padding 为 `24/40/24/24`。
- `frontend/lib/features/settings/presentation/tabs/automation_tab.dart` 中收藏同步运行列表、运行详情、预览确认和发现源编辑都使用 `AlertDialog`。
- `frontend/lib/features/accounts/account_center_page.dart` 的收藏预览使用 `_FavoritesPreviewDialog` + `AlertDialog`。
- `frontend/lib/features/review/widgets/favorites_sync_automation_panel.dart` 也有预览和详情 `AlertDialog`。
- `frontend/lib/features/auth/presentation/widgets/interactive_login_dialog.dart` 的扫码/交互登录使用 `AlertDialog`。

`frontend/lib/features/settings/presentation/widgets/setting_components.dart` 的 `SettingTile` 使用单行 `Row`：左侧图标、标题/副标题、右侧 trailing 控件挤在一行。`ExpandableSettingTile` 展开内容固定 `padding: EdgeInsets.fromLTRB(64, 0, 20, 24)`，在手机竖屏下会进一步吃掉可用宽度。包含 Slider、Dropdown、按钮组、密钥输入时很容易局促。

`frontend/lib/core/layout/responsive_layout.dart` 中 `getColumnCount()` 在宽度 `>= 360` 时就返回 2 列。360-430px 手机竖屏会显示双列收藏卡，这可能让卡片阅读和 card-to-detail 转场目标都过窄。

### 用户影响

- 手机竖屏下，弹窗左右 inset、内部 padding、固定 maxWidth 和 trailing 控件叠加后，实际可用输入宽度偏窄。
- 收藏同步结果、发现源编辑、分发规则、登录二维码等本质上是工作流，不是简单确认弹窗；用户需要查看上下文、错误、重试和日志入口。
- 多层弹窗会切断任务上下文。例如自动化页打开 run 列表，再打开 run 详情，再跳动态页日志，用户很难记住自己来自哪个平台/来源/目标。

### 建议设计

建立统一的响应式容器，而不是每个功能单独写 `AlertDialog`：

- `AdaptiveTaskSurface`：
  - 手机竖屏：全屏 route 或接近全高 bottom sheet，宽度使用完整 viewport。
  - 平板/桌面：居中 dialog，限制 maxWidth。
  - 支持标题栏、返回/关闭、主操作、次操作、错误区、日志入口。
- `AdaptiveSettingsTile`：
  - 窄屏下 trailing 控件下移到标题下方，Slider/Dropdown 占满宽度。
  - 宽屏下保留左右布局。
- `TaskResultPage`：
  - 对收藏同步 run、发现源同步 run、解析测试 run、推送测试 run、AI 连通性测试 run 提供可路由结果页。
  - 弹窗只用于确认，不承载完整结果和历史。

优先迁移对象：

1. 收藏同步预览、结果、失败列表。
2. 发现源编辑和发现源质量检查结果。
3. 分发规则编辑。
4. 交互登录/二维码登录。
5. 内容详情里的后处理失败详情。
6. 收藏库筛选器。

## P1: 二级界面过多，结果页和深链接仍不足

### 现状证据

`frontend/lib/routing/app_router.dart` 的主导航已经收敛为：

- `/home` 动态
- `/collection` 收藏库
- `/inbox` 收件箱
- `/automation` 自动化

辅助路由有：

- `/settings`
- `/agent`
- `/accounts`

这个方向是对的。但大量复杂功能仍停留在 tab、dialog、drawer 组合里：

- 自动化页内收藏同步 tab -> run 列表 dialog -> run 详情 dialog。
- 健康矩阵 -> 平台解析测试 dialog -> 动态页运行详情。
- 自动化页 -> 发现源编辑 dialog -> 同步/质量检查日志。
- 收藏详情 -> 后处理状态面板 -> 错误详情 dialog / toast 跳转。
- 收藏库 -> filter OpenContainer -> 内部 date picker dialog。

### 用户影响

这些入口能完成操作，但难以形成“我在哪里、这个任务结果是什么、我下一步能做什么”的稳定路径。用户无法把某个失败结果收藏、复查、分享给后续 agent，也难以从一个异常项反查相关账号、来源、内容和运行记录。

### 建议设计

把“任务结果”从弹窗升级为一等路由：

- `/automation/runs/:runId`
- `/automation/favorites-sync/runs/:runId`
- `/automation/sources/:sourceId/runs/:runId`
- `/automation/platforms/:platformId/health`
- `/collection/:id/processing/:runId`

动态页仍可以展示时间线，但详情应进入可路由页面或全屏 surface。移动端尤其需要这一点，因为抽屉和弹窗嵌套在竖屏上很不稳定。

## P1: 设置与前端功能面不完整

### AI 评分缺少开关

当前“AI 发现”设置包含兴趣画像、评分阈值、保留天数，但没有“启用 AI 自动评分/巡逻”的开关。后端也没有对应 schema 字段。用户只能调阈值，不能关闭评分行为。

建议新增：

- `enable_discovery_patrol`
- `enable_discovery_summary_writeback` 或在 `enable_discovery_patrol=false` 时禁止巡逻写回 summary/tags/state
- “手动评分仍可用”的显式说明和按钮状态

### 摘要开关语义不清

当前 `enable_auto_summary` 实际含义是“自动 post-ingest 摘要生成”，不是“任何 AI 摘要写回”。文案应改为更精确：

- 当前文案：启用 AI 自动生成摘要。
- 建议文案：解析后自动生成内容理解与 RAG 分块。

同时在 AI 发现设置中说明巡逻评分可能生成一句摘要，或拆分成独立开关。

### 语义索引缺少用户级策略

`PostIngestService.schedule_embedding_index()` 只要调用方传入 `embedding=True` 就会创建后台任务。它会在缺 key 时失败并记录状态，但没有“自动索引开关”。如果后续用户关心成本、隐私或本地离线模式，应把语义索引纳入同一策略层。

### 收藏同步仍需产品化

现有文档和代码已经显示收藏同步有平台级实现、预览、run 记录、部分失败诊断和重试。但它距离“自动同步登录账号收藏夹”仍缺：

- 收藏夹/分组级范围选择。
- 首次同步策略。
- 远端取消收藏后的本地处理策略。
- 完整失败列表页。
- 同步进度和取消/暂停能力。
- 与账号健康、平台限制、解析失败的统一关联视图。

这些不应继续散落在设置和自动化 tab 中，应进入账号中心/自动化健康矩阵的统一模型。

## P1: 文案和信息架构残留旧概念

### 现状证据

主导航和路由已经把旧入口重定向：

- `/dashboard` -> `/home`
- `/discovery` -> `/inbox`
- `/review` -> `/automation`

但代码和 UI 文案仍有旧概念：

- `frontend/lib/features/collection/widgets/dialogs/filter_dialog.dart` 的语义搜索 scope 标签仍有“探索池”。
- `frontend/lib/core/widgets/section_header.dart` 的注释示例仍写“探索概览”“前往探索”。
- `frontend/lib/features/dashboard/widgets/discovery_overview_card.dart` 注释为“探索概览饼图卡片”。
- 自动化页仍大量使用“发现来源”“发现源”，这部分作为 source domain 可以保留，但需要和“收件箱”入口关系讲清楚。
- 内部模块仍叫 `dashboard/discovery/review`，这可以作为兼容遗留暂时保留，但新增用户文案不应继续扩散旧名字。

### 建议设计

统一用户心智：

- “动态”：运行、异常、下一步。
- “收藏库”：长期资产和检索。
- “收件箱”：待决策候选，包括发现、同步候选、Agent 推荐、解析失败。
- “自动化”：规则、账号、来源、推送、任务策略。

文案层面：

- “探索池”改为“收件箱”或“发现候选”，取决于真实 scope。
- “审核”仅用于分发队列审核，不再作为页面级概念。
- “发现源”保留为自动化中的输入源类型，但收件箱页面不再叫探索库。

## P1/P2: 收藏库密度和详情阅读体验需要重新取舍

### 现状证据

`ResponsiveLayout.getColumnCount()` 在 `width >= 360` 时直接返回 2 列。手机竖屏下收藏卡片会很窄。对于图片瀑布流这可能提升浏览效率，但对文章标题、作者、标签、处理状态和 shared transition 都不友好。

内容详情页顶部 action buttons 横向排列 5 个图标按钮：生成摘要、重新解析、编辑、删除、阅读原文。在窄屏下如果 app bar 右侧空间不足，可能产生拥挤或溢出风险。

### 建议设计

- 手机竖屏下默认单列或提供密度切换：舒适/紧凑。
- 双列只用于图片主导内容或用户显式选择。
- 内容详情 actions 在移动端收敛为主按钮 + overflow menu。
- 卡片进入详情的视觉目标优先保证阅读身份连续，而不是强行保持瀑布流密度。

## P2: 语义搜索/RAG 仍是搜索模式，不是问答模式

### 现状证据

`frontend/lib/features/collection/providers/collection_provider.dart` 在 semantic mode 下调用 `/search/semantic`，把返回结果转换成 `ShareCardListResponse`，并固定 `hasMore=false`。这说明当前语义能力是 top-k 搜索，不是完整 RAG 问答。

前端筛选 dialog 中 semantic scope 有 `library/discovery/all`，但用户侧标签仍有旧的“探索池”。

### 建议设计

收藏库搜索应最终拆成：

- 关键词搜索。
- 语义搜索。
- 问答/RAG。

RAG 回答必须能回链到内容和片段，并解释使用范围。否则它不应作为独立主导航项，只应作为收藏库的搜索模式之一。

## P2: 前后端能力状态需要从“配置字段”升级为“用户可理解能力”

当前后端已有 `/api/v1/ai/capabilities` 和一些连通性测试入口，这是正确方向。但设置页仍有较多模型字段、API key、版本号、provider 细节。用户真正需要先看到：

- 内容理解是否可用。
- 自动摘要是否会自动运行。
- 发现评分是否会自动运行。
- 语义检索是否可用。
- Agent 是否可用，是否允许执行工具。

高级配置可折叠保留，但能力状态和自动策略必须在同一个位置。

## 建议实现顺序

### 第一阶段：修正可信度最高的问题

可并行拆成三条线。

**后端策略线**

1. 增加统一 `AutomationPolicyService`，本阶段先覆盖自动摘要、发现/收藏同步、分发、Cookie 保活和解析/后处理策略。
2. 新增核心策略键：`enable_discovery_patrol`/`enable_ai_scoring`、`distribution_mode`、`enable_cookie_keepalive`、`ingest_mode`。
3. 让 discovery sync、favorites sync、post-ingest、manual summary、manual patrol、distribution enqueue 都显式声明 `trigger=auto/manual/retry`。
4. 后台自动任务必须经过策略检查；手动覆盖 disabled 对象时要求 `force=true` 或更高风险确认。
5. 更新 processing status、AI capabilities、favorites status、platform health、background diagnostics 和 settings response，展示“关闭的是自动行为、手动能力还是外部副作用”。
6. 增加后端测试：关闭自动摘要、关闭巡逻评分、暂停分发、关闭 Cookie 保活、disabled 来源/平台默认不被手动同步。
7. 暂缓项：`enable_auto_embedding`、semantic reindex 策略、`agent_mode`、Agent tool allow/deny、Agent 触发外部副作用拦截暂不进入本阶段实现。

**前端转场线**

1. 把详情页目标 Hero 从空白 surface 改为真实首屏 header。
2. 保持 loading preview 到 loaded header 的连续过渡。
3. 检查文章/图集/视频/纯文本四类内容。
4. 用提权 Flutter 测试验证桌面、手机竖屏和返回路径；必要时再补人工截图。

**自适应容器线**

1. 建立 `AdaptiveTaskSurface` 和 `AdaptiveSettingsTile`。
2. 先迁移收藏同步预览/结果、发现源编辑、分发规则、登录 dialog。
3. 移动端使用全屏或近全屏 surface，桌面保留 dialog。

### 第二阶段：把后台任务结果做成一等体验

1. 新增 task run 结果页路由。
2. 收藏同步、发现源同步、平台解析测试、推送测试、AI 连通性测试都能从动态页、自动化页、账号中心跳到同一类结果页。
3. 完整失败列表和单条重试入口从弹窗迁移到结果页。
4. 健康矩阵行级异常直接链接到对应 run、账号、来源或目标。

### 第三阶段：收件箱和收藏同步产品化

1. 把收藏同步候选、解析失败逐步纳入收件箱；Agent 推荐暂缓。
2. 增加收藏夹/分组范围选择。
3. 增加首次同步、取消收藏、删除/保留/归档策略。
4. 支持同步进度、暂停、取消和完整历史。

### 第四阶段：信息架构和文案收敛

1. 全局扫描用户可见“探索/发现/审核/推送”文案。
2. 保留“发现源”作为自动化输入源，其他页面尽量使用“收件箱/候选/动态/自动化”。
3. 调整手机收藏库默认密度和详情 action overflow。
4. 语义搜索/embedding/RAG 相关升级暂缓；本阶段只整理现有文案和入口，不扩展语义能力。

## 验证建议

### 代码测试

  - 后端：用 `.venv\Scripts\python.exe -m pytest backend/tests -q` 跑策略相关回归。
  - 前端：Flutter/Dart 命令需提权执行，至少跑 `flutter analyze`、相关 widget tests 和全量 `flutter test`。
  - 策略回归至少覆盖：
  - 关闭自动摘要后，自动 post-ingest 不写入摘要；手动摘要必须带 `trigger=manual` 记录。
  - 关闭 AI 评分后，发现同步不调用 patrol scoring，不写入 `ai_score/ai_reason/ai_tags/summary`。
  - disabled 发现源默认不能被手动同步，除非接口显式 `force=true`。
  - disabled 收藏平台默认不能被单平台手动同步，除非显式覆盖。
  - `distribution_mode=paused` 时，规则刷新、解析完成、trigger-run 都不能产生外部推送。
  - 关闭 Cookie 保活后，leader 启动不应启动平台保活循环，账号页状态应展示已暂停。
  - 暂缓项不进入本阶段回归：自动语义索引开关、semantic reindex 覆盖语义、Agent 工具权限策略。

### 产品验收

1. 关闭自动摘要，添加普通 URL，确认 post-ingest 不生成摘要/RAG 分块。
2. 关闭 AI 评分，配置 RSS/Telegram 发现源并同步，确认不会自动评分、不会自动写入 `ai_score/ai_reason/ai_tags/summary`、不会自动按阈值改变可见状态。
3. 禁用某个发现源后，从自动化页和健康矩阵分别尝试同步，确认默认拒绝或要求“临时同步已禁用来源”的二次确认。
4. 关闭某平台收藏同步后，确认“自动同步”与“手动同步”语义分离：自动任务不运行，手动同步要么禁用，要么明确提示覆盖。
5. 暂停分发后，修改规则、解析新内容、点击 trigger-run，确认不会产生外部推送。
6. 关闭 Cookie 保活后，重启后端并等待 leader 初始化，确认账号页显示保活暂停，后端不再启动该平台保活循环。
7. 手动点击生成摘要，确认 UI 明确这是手动动作，并返回 run 结果。
8. 收藏卡片进入详情，用 widget/route 测试证明详情目标 Hero 是真实 header，而不是只在飞行层存在。
9. 窄屏布局测试覆盖收藏筛选、分发规则、发现源编辑、收藏同步结果、登录二维码，确认没有过窄输入区、截断按钮或多层弹窗迷失。
10. 收藏同步失败一次后，确认用户能从账号中心、自动化健康矩阵、动态页进入同一个 run 结果，并看到完整失败原因和下一步动作。

## 结论

当前主导航方向基本正确，不建议重新回到“五底边项”或为 Agent/RAG/时间线继续增加底边栏。真正需要大改的是横切策略、任务结果页和响应式复杂操作容器。

优先级最高的是 AI 自动化策略统一、收藏卡片转场真实落地、移动端弹窗体系重构。这三项解决后，用户才会相信“设置里的开关真的控制后台行为”“动画不是表面效果”“后台任务失败后知道去哪里处理”。

embedding/语义索引和 Agent 工具权限仍是已知架构风险，但按当前实施边界先不做；后续重新启用时，需要回到本文对应章节重新核对代码路径和验收范围。
