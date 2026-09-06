# VaultStream：核心链路精简与可用性修复任务书

## 状态、依据与 Goal

状态：`completed-with-known-limit`（原实施任务结果，见文末记录；当前工作区复核单独记录）。2026-09-05 审计后建立的有限实施任务书。详细依据见 [repository-audit.md](../issues/repository-audit.md)。审计基线为 `main@fba018edcafc9fe1fd3a15208b087c9ef9277eb1`，当时工作区干净。

Goal：在保留现有捕获、解析、收藏、搜索、审批和分发能力的前提下，使解析任务按唯一身份正确结算、禁用平台的重试遵守现有控制策略、手机正文可用、跨导航收藏状态一致、Agent API 目录恢复；删掉因此被替代的重复业务路径，补真实回归测试并同步相关文档。完成依据是可观察行为与明确责任减少，不是单纯测试数量、代码行数或另一份计划。

产品约束：用户于 2026-09-05 明确确认，[前端信息架构方案](2026-06-10-frontend-information-architecture-redesign.plan.md) 与 [系统构想](2026-07-15-vaultstream-system-concept.plan.md) 基本覆盖产品真实期望和功能需求，以两者为准。产品是覆盖捕获、归档、理解、探索、行动的自托管个人知识流；当前切片先修基础可靠性，不将长期目标缩成收藏工具。文档明确的功能属于已确认需求，未实现与本次 Out of scope 均不表示未获确认；文中条件性方向、未定原型细节和切片实施约定继续适用。

## In scope

| ID | 执行边界 | 完成结果 |
| --- | --- | --- |
| VS-Q01 | pytest 源码根/CI 收集入口、相关 DNS 测试夹具；前端已知三条 analyzer info 的最小修正 | 基线命令可复现，SSRF 检查与断言不削弱；记录仍有的环境差异 |
| VS-U01 | AppShell 的窄屏 bottomNavigationBar 尺寸/安全区 | 三个主分支正文可见、可用，横屏和缩放不溢出 |
| VS-U02 | 主导航切换时的收藏查询/筛选保留，显式重置同步 | 输入、筛选、结果和返回位置一致 |
| VS-A01 | 解析 Task 唯一身份、成功/失败/跳过/取消结算、两套重试执行收敛；入队失败透明化 | 不再批量结算同内容任务，不把失败写为完成，不假称已入队 |
| VS-A02 | favorites run/item/batch retry 复用已有 policy、单项/批量导入编排去重及必要 UI 错误提示 | 禁用无副作用，允许路径及逐项失败结果保留 |
| VS-A03 | API catalog 改用公开 OpenAPI，保留目录响应及权限过滤 | 实际 app 的受控端点可见，无私有路由树 fallback |
| VS-C01 | DistributionEngine 空子类/导出、scheduler 纯测试透传层 | 删除无职责旧名，保留真实服务和异步 session 生命周期 |
| VS-D01 | 本轮相关模块/API/页面/issue 文档，以及审计明确指出的状态和事实失真 | 当前实现、未验证和愿景明确区分，不重建总路线 |

## Out of scope

- VS-A04：统一任务中心、通用结果 renderer、新任务数据库迁移、lease/自动崩溃恢复和历史任务回放。
- VS-A05：媒体全链路迁移、删除存量 legacy 字段、代理/对象存储重写、缓存框架替换。相关问题可以更新证据，不在本次修复。
- VS-A06：人工修改不得被重解析静默覆盖、结果需可比较/接受/合并/保持的目标已确认；完整版本保护与交互作为后续切片，本次 A01 不扩大覆盖语义或迁移用户数据。
- VS-A07：扩展或全面重做 Agent 工具权限、全局 SSE 重写、会话产品重做。
- VS-U03：动态推荐流、通知中心、账号独立页、Agent 常驻入口、整套卡片/阅读器/自动化信息架构重做。
- 长期构想中的事件聚合、原生后台播放/PiP、OCR/PDF/RAG 问答、Browser Agent、多租户、Rust、新平台支持。
- Redis/Celery/新工作流引擎、全仓依赖升级或锁定项目、无关大文件拆分/格式化、安全扫描全量整改。
- 自动提交、push、PR 发布、部署、真实平台登录/抓取、外部消息发送、真实数据迁移或清理。可以使用无外部副作用的隔离测试。

## 不可破坏的约束

1. 开始先读适用 AGENTS，检查 branch/HEAD/status；仅复核本任务依赖的事实，不重新开展无边界全仓审计。用户已有修改不覆盖、不回滚、不替用户清理。
2. 先读相关模块、页面、API router/schema/service/client/tests 与 docs/backend/api.md 再改 contract。文档与代码冲突要记录。不得猜字段/成功条件，新增错误必须明确类型和客户端处理。
3. 保留 URL 去重、ContentSource、人工编辑数据、layout override、存量媒体访问、审批/分发规则、认证失败分类、限流/超时、重试幂等与部分失败结果。
4. 保留鉴权、Bot 权限、SSRF/DNS/重定向/路径安全、密钥脱敏；不新增 Agent 的跳过确认/策略路径。默认不触发真实外部副作用。
5. 替换后删除旧循环、别名和透传，不能长期保留 runtime fallback、猜字段双路径或吞错成功。仍有真实存量消费者的媒体 legacy 本轮不删。
6. API 的成功响应、同步/异步性质及路由保留。允许本任务明确限定的错误纠正：入队失败显式 503；策略拒绝复用现有 409 格式。若发现必须破坏其他公开契约才能实施，先停该项。
7. 后端正式测试用仓库根 `.venv/bin/python`，测试位于 backend/tests；临时外部探针放隔离位置，用后删除。任何 Flutter/Dart 命令必须申请提权在沙盒外执行；不能执行就如实标为未验证。
8. 先补能发现真实回归的必要测试，再小步修改。不得删断言、全量 mock 链路、放宽类型/安全检查、降低覆盖率规则、隐藏报错来制造通过。保留既有失败与新回归的区别。

## 执行顺序与依赖

批次 0 建立可复现基线；批次 1 前端可独立完成；批次 2/3 分别处理解析和同步；批次 4 修目录并去小空壳；批次 5 做关联文档与最终验收。不要为了等一个产品决定停止其他独立批次。各批次可独立检查，但最终串行整体验收一次；不因任务书存在就自动创建每个批次的子计划。

### 批次 0：恢复验证入口（VS-Q01）

问题：从 backend 启动 pytest 时根 scripts 无法导入；safe_fetch 测试的 httpx mock 并未隔离 DNS；Flutter 当前环境有三条 lint info。

涉及：backend/pytest.ini、.github/workflows/quality.yml、backend/tests/test_scripts/test_dev_controller.py、backend/tests/test_adapters/test_fetcher_exceptions.py 及 tiered fetch 相关测试，frontend/lib 中的 detail_sections.dart。

推荐做法：在现有 pytest 配置显式包含 backend 与仓库根两个 import 根，使 CI 原启动方式可用；避免在测试各处加 sys.path。为需要公网成功路径的测试设置确定、无网络的 DNS fixture，保留私网地址/重定向拒绝断言，不改变生产 safe_fetch。三条 lint 只作等价表达修正。

拟删除：错误导入路径假设、测试对真实 DNS 的隐含依赖；不删除安全校验/失败断言。不改变全仓 dependency 范围来掩盖 A03。

验证：backend cwd 原 pytest 命令能收集 scripts 测试；DNS fallback/timeout/私网拒绝场景稳定；监听端口需要权限时单独按规定执行；记录 Python、FastAPI、Flutter 与解析依赖版本。前端 analyze 不能仍有本批次已知的三条 info。

完成条件：上述针对性测试通过；其他基线失败按 ID 留给后续批次，不要求先伪造全绿。

### 批次 1：恢复手机正文与导航状态（VS-U01 / VS-U02）

问题：_MobileShell 的无限竖向伸展 Row 占满 Scaffold；AppShell._onDestinationSelected 无条件清收藏 filter，搜索控制器未清。

涉及：frontend/lib/layout/app_shell.dart、core/layout/responsive_layout.dart、routing/app_router.dart、collection filter/provider/search widget；先读 navigation.md、components/navigation-shell.md、pages/collection.md。

推荐做法：以标准 NavigationBar 的有限高度布局底部主入口和工具菜单，正确处理 SafeArea，不重写断点体系。分支切换复用 StatefulShellRoute 保留状态；只有现有明确重置动作清空，输入框/provider 同步。若重复点击当前主入口有返回根页行为，保留其合理导航职责，不将普通分支切换当清空命令。

拟删除：导致 body 为 0 的 stretch/约束组合；跨分支 clearFilters 的隐式副作用。不要新增第二份查询状态或“移动端特殊 fallback”。

验证：用真实 AppShell、StatefulShellRoute、ProviderScope 的 widget 测试断言正文位置/尺寸与可点击元素，不只找标签。至少 360×800、600×900、800×360、1200×900；关键边界 799/800 按当前真实 mobileBreakpoint 再核对。补文字缩放 1.0/1.5/2.0、安全区和导航切换/返回。查询+筛选→自动化→收藏后输入值、chips、结果范围与滚动位置一致；显式重置同步清除。

人工验收：隔离本地 Web，合成长中文内容、无媒体内容及失败项；窄屏能浏览/打开详情/返回；横屏短高度可读；保存修改后手机/横屏/桌面截图，至少核心收藏在浅/深主题完成内容加载。桌面键盘可达搜索、导航和主要操作，焦点不被隐藏正文困住。真实 API 或最小确定 fixture 可用，但须标明边界，不能用纯静态 mock 页面证明交互。

完成条件：真实 shell 回归通过、截图正文有合理空间、现有 98 项前端测试不回归；未验证原生端明确报告。U03 的首页/通知/卡片重设计不在此批次。

### 批次 2：唯一解析任务与单一执行器（VS-A01）

问题：Task 领取后丢行身份，按 content_id 批量完成；finally 把解析失败结算成功；队列和 retry_parse 各自重试；入队失败返回 False 被忽略。

涉及：backend/app/core/queue_adapter.py、tasks/parsing.py、tasks/runner.py、services/content_service.py、routers/contents.py、Task/Content 模型、对应 schema 与前端解析 API 调用；先读 contents、events-tasks 模块与 API/数据库文档。

推荐方案已经选定：保留 SQLite + SQLAlchemy，不引入队列框架、不迁移存量 Task。利用已有 Task 主键作为领取/结算身份，保留日志 task_id 与 content_id 各自作用；内部领取结果必须明确表达数据库身份，不能与外部 payload 同名字段混用或从 content_id 猜回。完成和失败只更新该行的允许前置状态；运行中存在性查询要支持多个匹配，不能异常后当不存在。

将解析重试、可重试/认证错误分类和必要后处理收敛为一个执行路径；保留队列入口与 HTTP 同步/后台入口的运输职责和现有响应形态。成功/跳过/失败显式结算，finally 只释放 adapter 等资源。取消不可记成功；保持可诊断的失败/未完成，不新增自动回放。解析成功后的索引/审批副作用必须保持幂等，不因合并重复调用。

入队失败采用最小方案：检查队列写入结果，抛出明确业务错误并在相应 HTTP 边界映射 503，成功文案只在入队成功后产生；内容若已提交则保留为可重试状态，不删已保存数据/来源。再次提交同 URL 应通过既有去重重新尝试入队。统一已涉及的调用方错误处理，不增加“失败转后台偷偷重试”的隐藏分支；先在 schema/API 文档与测试明确此错误。

拟删除：按内容批量结算路径、无条件 finally 完成、retry_parse 的第二套重试业务循环、假成功日志/响应。若 HTTP 入口仍需要 wrapper，里面只保留响应与调度职责，不留重复业务实现。

必须保留：已成功内容的跳过/显式 force 语义、layout override、来源/手工字段的当前保护、审批策略、adapter.close、错误诊断。若统一解析涉及文档未定义的手工内容迁移/合并细节，停止该子项并说明 A06 的具体实现问题，先交付已可独立完成的身份/终态修复，不自行设计版本库。

必要测试：

- 同 content 的两个 Task 均被领取，完成一个后另一个仍 RUNNING；失败只影响指定任务；重复结算幂等，伪造 payload 不能改结算对象。
- 确定性耗尽 retry、auth_required、non_retryable、成功、已成功跳过、内容不存在、取消；Content/Task/run 可观察状态不矛盾，attempt 含义清楚。
- 队列与手动入口共用执行器，错误分类/重试次数符合 contract；资源关闭与后处理次数真实断言，避免只 mock 整个 executor 后声称循环正确。
- 入队失败注入覆盖新内容、已存在失败内容、重置为未处理；错误可见、保留数据、再次提交不复制内容；至少一项真实 SQLite 入队/领取/结束测试。
- 既有解析 adapter/任务、内容 API/服务、审批/分发测试不回归；不发真实网络或消息。

完成条件：上述故障不再复现；旧循环/按 content 结算调用已消失；公开 HTTP 成功契约保持，503 明确处理；状态改善由集成到真实数据库的测试证明。崩溃恢复不作为本批次承诺。

### 批次 3：同步重试控制与编排收敛（VS-A02）

问题：run/item/batch retry 漏 policy；单项与批量在 system router 重复做 ContentService 导入/来源/结果处理。

涉及：routers/system.py、tasks/favorites_sync.py、services/automation_policy.py、services/content_service.py、相关 request/response schema、favorites_sync_provider、favorites_sync_automation_panel；关联 issue 为 favorites-sync-retry-policy-gap.md。

推荐：复用 AutomationPolicyService.favorites_platform_manual，在创建 retry run 或首次导入之前校验；不要另建能力矩阵或允许旁路。单项/批量共用 favorites 领域内的导入/记录编排，router 只映射请求、结果与策略错误。沿现有 force 和 allow_manual_favorites_sync_disabled_platform contract 保留明确授权覆盖；默认拒绝禁用平台，不新增隐式强制、平行开关或模糊“成功但没做”的返回。

run=all 按当前启用平台处理，避免把历史禁用平台重新启用；单平台与混合批次按已读 contract 给明确逐项/整体策略结果。若现有 contract 对混合平台拒绝语义不清，先补类型与测试，选择不触发被拒平台副作用的最小行为，不改变已成功项的来源/游标/错误记录。

UI 使用既有 client 的结构化错误，在禁用时显示原因、阻止误操作；服务端仍是权威边界。Agent api_mutation 即使经过用户确认，也必须受到相同领域 policy；不能以确认代替平台启用。

拟删除：三个入口各自绕过策略的路径、单项/批量重复导入业务块、泛化旧 issue 中错误的“还不存在策略服务”描述。不把所有 system.py 路由整体搬家当作精简成果。

验证：三类 retry 对禁用平台都不创建执行性 run/不导入，返回明确既有 409 policy 格式；启用成功、显式现有 override、all、部分失败、重复项、来源/历史均覆盖。Agent 用真实 ASGI route 调用验证拒绝（仅拦外部导入），不要只测工具注册。前端单测/widget 覆盖禁用原因与错误/部分失败，不能仅隐藏按钮当安全证明。

完成条件：控制面与所有已涉及入口一致，共同编排只有一份；保留现有功能和 contract，相关测试通过。

### 批次 4：公开目录与无职责旧层（VS-A03 / VS-C01）

A03 涉及 services/agent/tools/api_bridge.py、agent 工具测试。使用 app.openapi()['paths'] 的 HTTP operation 清单，保留路径 allow/block、prefix、include_mutations、read/confirmation_required 与现有响应字段。name 从公开 operation 元数据稳定映射，先核对消费者，不猜框架私有属性。删除原平铺 app.routes 逻辑，不保留旧版 fallback。

验证实际 include_router app、GET /contents、读写过滤、禁止 Agent 自递归和 binary、路径 prefix、响应 schema/字段；现有目录测试通过。无新增依赖、迁移或权限范围，FastAPI 官方依据见审计 A03。

C01 涉及 services/distribution/engine.py、__init__.py、scheduler.py 和消费者测试。重新搜索所有导出/配置/动态引用，确认仍只有空别名与测试替身后删除 DistributionEngine 和 _enqueue_content_impl 纯透传；测试直接约束 DistributionService 与公共调度入口。保留后台 wrapper 的 session 生命周期与错误处理，不能用全 mock 删除这些责任。

完成条件：实际服务测试、策略 enqueue、后台 session 关闭正确；没有遗留旧导出/兼容别名。若新代码已赋予该层真实职责则记录证据、取消该项，不为凑减法强删。

### 批次 5：文档事实同步与整体验收（VS-D01）

按已实现行为更新相关后端模块/API、前端页面/导航、issue；检查 OpenAPI inventory 缺 POST /api/v1/ai/models 并按真实 schema 补足。同步 plans 索引中的媒体/解析状态与历史限制；前端当前文档去除不存在的首页趋势/时间线、旧 overlay 成品描述；search-rag 区分已写的混合检索与尚未验证/尚未实现的问答；旧 policy/media issue 写清当前剩余问题。

记录用户已明确确认两份文档为目标依据；不再把其目标标为未经确认的 AI 推演，也不让当前模块文档否定权威目标。修 issues 索引的已删除总路线引用、已归档反引号路径。保留历史决定的原因，不复制整个报告到各模块。不为每个修复新增 plan/process；确需跨会话进度时只维护本任务同名 process。

最终记录每个 ID：完成/阻塞/未验证、行为证据、删掉的旧职责/路径、新增的类型/边界与成本；不只报 LOC。审计原始基线保留为历史，追加处置链接/状态，不把原来失败记录改成从未存在。

## 验证基线与运行条件

后端必须使用根虚拟环境。以下按本仓库实际路径核实；新 worktree 若没有 `.venv`，先确认可复用源 checkout 根虚拟环境的绝对 Python 路径，不使用系统解释器，也不把临时实验环境变化提交进去。

```bash
# 仓库根目录；先记录版本、Git 状态
.venv/bin/python -m pytest backend/tests -q -m "not integration"

# backend 工作目录；Q01 完成后应可用，亦是当前 CI 形态
../.venv/bin/python -m pytest tests -q -m "not integration"
../.venv/bin/python ../scripts/check_backend_requirements.py
../.venv/bin/python ../scripts/check_openapi_docs.py ../docs/backend/api/endpoints.md
../.venv/bin/python ../scripts/check_database_schema.py
```

schema gate 必须指向临时测试数据库，不用真实业务库；修改环境变量前读当前 config 与脚本。两种 pytest cwd 用于首次证实入口修复，之后选择 CI 形态做一次全量回归，不无理由反复跑全套。

```bash
# frontend 工作目录；所有 flutter/dart 命令按 AGENTS 提权执行
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter build web --release
```

构建/浏览器验收按真实 client 编译配置传临时 API 地址及非敏感测试 token；不把示例 token 当生产设置。启动只读 UI 审计环境时不跑正常后台 workers/真实 Bot，不使用已有 `.env` 凭据；正式变更涉及写操作则用隔离数据库和确定的外部边界替身完成行为测试。

审计已有结果：backend cwd 收集 error；repo cwd **813 passed / 3 failed / 5 errors / 4 skipped / 9 deselected，66% coverage**。其中端口监听单测提权重跑 **1 passed**；API catalog 失败属于 A03；tiered fetch 与 5 个 teardown errors 需核对 DNS 夹具。前端 **98 passed**，analyze **3 info 非零退出**，Web build 成功。临时新增探针另证实 A01/A02/U01，不包含在既有测试计数中。

版本限制：审计 Python 3.11.16、FastAPI 0.141.1、Starlette 1.6.0、SQLAlchemy 2.0.52；CI Python 3.13 且未完整锁依赖。Flutter 3.47.1/Dart 3.13.1 的隔离离线解析更新了 191 项锁定结果，不能引用为原 lock 的通过证明。执行时优先验证实际受支持环境/原 lock；有升级必要需明确理由与影响，不顺带升级全仓。

最低跨层回归：SQLite 解析任务/内容终态；真实 API 的 disabled retry；真实 FastAPI API catalog；真实 Flutter shell 的窄屏与状态保留。外部平台集成测试标 integration，未经授权不调用。单元测试与模拟浏览器不能代替真实平台、原生包或部署验收。

## 风险与停止条件

- 遇到删用户数据、不可逆 schema/媒体迁移、真实平台或消息副作用：不执行，报告具体阻塞。
- 不改变权威文档明确的人工保护和主入口职责；仅当触及文档未定细节、两份权威文档自身冲突或本次范围外实现时，停止对应子项说明问题，继续其他独立工作。
- 需要新增重型依赖、服务或改变本任务已选架构：不自行替换，说明已验证的不足与最小需要。
- 新 HEAD 已修复某发现或新增真实消费者：按证据调整/取消该项并记录，不能机械应用旧结论。
- 自动审批拒绝工具动作时，可选合规的低风险验证；确实受阻要解释拒绝动作与原因，不把未执行写成通过。
- 单项测试确为环境所限：保持断言，记“未验证/环境阻塞”，不能忽略或跳过到全绿。可执行的其他验证继续。

## Definition of Done

1. In scope 每项都有可检查的行为验收、正式回归测试与完成/阻塞状态；失败原因可见，没有虚假成功。
2. 解析唯一身份/终态与同步禁用策略经过真实数据库/API 边界验证；成功、失败、跳过、重试、取消的行为不互相矛盾。
3. 手机/窄平板正文恢复，跨导航查询/筛选一致；关键断点、缩放、安全区、深浅主题和主要键盘路径有测试或明确未验证说明，并交付必要截图。
4. 队列与 HTTP 的重复解析循环、按内容结算、同步重复导入、空分发别名和旧目录扫描实际删除。没有为“保险”永久保留新旧业务路径。
5. 必要检查通过，既有失败与新增回归区分清楚；无法覆盖的 CI 版本、原生端、真实平台、性能/崩溃恢复和部署状态如实报告。
6. 当前模块/API/页面/issue 与实现一致；保留未决范围及人工数据约束，不宣称整份长期蓝图已完成。
7. 工作区只包含本任务必要改动；无真实凭据、临时探针、测试数据库、外部捕获日志；未自动提交、push 或部署。
8. 最终报告说明净复杂度变化：合并了什么职责、删除了哪些旧路径、为正确性新增哪些必要边界、遗留什么。不得以“已重新制定计划”代替实施。

## 当前工作区执行约定

原实施任务已完成。用户后续明确要求直接在 `/Users/ienone/coding/vaultstream` 当前工作区变更，不再为这些改动创建新任务或 worktree，也不通知已完成任务。检查其结果后将相关改动合入当前工作区，保留本次需求确认和用户已有修改；后续按当前工作区状态继续，不自动提交、push 或部署。

## 2026-09-05 实施结果

| ID | 状态 | 行为与边界证据 |
| --- | --- | --- |
| VS-Q01 | 完成 | `backend` 工作目录可收集根 `scripts`；公网成功夹具改为确定 DNS，同时保留私网/重定向拒绝；三条 analyzer info 已作等价修正。Python 3.11.16、FastAPI 0.141.1、Starlette 1.6.0、SQLAlchemy 2.0.52、pytest 9.1.1、httpx 0.28.1。 |
| VS-U01 | 完成 | 手机底栏改为有限高度并由 SafeArea 约束；真实 AppShell/StatefulShellRoute 测试覆盖 360×800、600×900、799×900、800×360、1200×900 和 1.0/1.5/2.0 文字缩放，正文尺寸及主入口可点击。 |
| VS-U02 | 完成 | 普通分支切换不再清空收藏查询/平台筛选；显式清空同步 controller 与 provider。真实 shell 测试验证往返后的输入、chip、过滤结果和滚动位置。 |
| VS-A01 | 完成 | `ClaimedTask` 保留数据库主键，完成/失败只结算指定 RUNNING 行；`ParseExecutionResult` 收敛队列与手动解析；成功、跳过、失败、取消显式终态；入队失败用 `ParseQueueUnavailableError` 映射 503，并保留已提交内容供重试。SQLite/API 测试覆盖同内容双任务、伪造 payload、重复结算、错误分类、单执行器及三类入队失败。 |
| VS-A02 | 完成 | run/item/batch retry 在执行或导入前统一检查 `favorites_platform_manual`；`all` 只处理当前启用平台；`import_items` 成为唯一导入/来源编排。真实 ASGI Agent mutation 不能绕过 409 policy，前端显示结构化原因。issue 已归档。 |
| VS-A03 | 完成 | API catalog 只读取公开 `app.openapi()['paths']`，保留路径、方法、权限和 mutation 过滤；`include_in_schema=False` 不再泄漏，无私有 route-tree fallback。OpenAPI inventory 已补 `/api/v1/ai/models`。 |
| VS-C01 | 完成 | 删除无职责 `DistributionEngine` 及导出、删除 scheduler 的纯测试透传；后台入口直接使用 `DistributionService`，仍保留异步 session 生命周期和错误边界。 |
| VS-D01 | 完成 | 同步 backend/frontend/API/plans/issues 文档；历史构想、当前实现、已归档问题和未验证边界已分开表述，审计基线原文保留。 |

净复杂度变化：删除按 `content_id` 批量结算、解析第二套重试循环、favorites 单项/批量重复导入、私有路由树扫描、空分发别名与测试透传；只为真实正确性新增领取身份、解析结果、入队失败和共享导入四个明确边界，没有保留新旧运行时 fallback。

最终验证：后端 `-m 'not integration'` 为 **830 passed / 4 skipped / 10 deselected**（本地端口用例因沙盒限制从全套中单独移出，并在沙盒外 **1 passed**）；核心变更组合测试 **149 passed**；requirements、131 条 OpenAPI inventory、临时 SQLite schema gate 均通过。Flutter `analyze --no-pub` 无问题、`test --no-pub` **104 passed**、release Web build 成功。浏览器使用真实 Flutter Web client 和只读确定 fixture，未启动 workers、Bot 或真实外部调用：

- [360×800 深色收藏](../issues/assets/simplification-and-ux/collection-mobile-dark-360x800.png)
- [800×360 浅色收藏](../issues/assets/simplification-and-ux/collection-landscape-light-800x360.png)
- [1200×900 浅色收藏](../issues/assets/simplification-and-ux/collection-desktop-light-1200x900.png)

已知限制：未运行需访问百度图片的外部 integration 用例；未验证 CI Python 3.13、原生安装包/真机触摸、TalkBack/VoiceOver、浏览器完整键盘链路、真实平台和部署。Flutter 准备环境曾重新解析 191 项依赖，tracked lock 已恢复，因此本结果不冒充“原 lock 在全新环境已证明可解析”；Web build 的现有 `flutter_secure_storage_web` Wasm dry-run 提示不影响 JavaScript release build。A04/A05/A06/A07/U03 及崩溃恢复仍按 Out of scope 保留。

## 当前工作区接收复核

以上为原实施任务记录。按用户后续要求，修复已合入 `/Users/ienone/coding/vaultstream`，后续直接在此工作区变更，未通知旧任务或新建任务/worktree。关键代码及正式测试与原交付一致，需求判断按两份权威文档及本次用户确认修正。

本工作区重新验证：后端 **830 passed / 4 skipped / 10 deselected**，被单独排除的本地端口用例 **1 passed**；requirements、131 条 OpenAPI inventory、临时 SQLite schema gate 通过。前端先解决旧缓存的生成代码缺失，再完成 codegen、analyze 无问题、**104 项测试通过**；锁文件及分析配置已恢复，无依赖升级改动。此次未重新 build Web 或进行浏览器交互验收。

VS-U01 的完整移动端视觉验收仍有限制：原 360×800 截图右侧裁切，不能单凭该图认定整页及全部导航可见；需正确视口下补验后才能关闭这一视觉证据缺口。现有 widget 回归通过与该截图限制并列记录，详见 [当前工作区复核](../issues/repository-audit.md#2026-09-05-当前工作区复核与需求更正)。此限制不等于已定位了新的布局根因。
