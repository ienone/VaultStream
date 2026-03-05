# 📋 VaultStream 后端测试进度追踪表

本文档用于记录 VaultStream 后端测试覆盖率的提升进度、已完成的任务及后续计划。

## 📈 整体进度概览

| 日期 | 整体覆盖率 | 已通过测试用例 | 状态 | 备注 |
| :--- | :--- | :--- | :--- | :--- |
| 2026-03-03 | 36% | 77 Passed, 10 Skipped, 1 Error | 🔴 基础薄弱 | 核心逻辑“裸奔”，Adapter依赖网络 |
| 2026-03-04 | 40% | 34 Passed, 0 Skipped | 🟡 核心受控 | 完成全平台 Mock，补齐核心 Task 测试 |
| 2026-03-05 | **53%** | **148 Passed, 4 Skipped** | 🟢 深度稳健 | **核心模块覆盖率实现 200%-400% 增长** |
| 2026-03-05 | **57%** | **419 Passed, 5 Skipped** | 🟢 持续推进 | Phase 1+2 核心服务层 6 模块覆盖率大幅提升 |

---

## 🏗️ 模块测试详情

### 1. 平台适配器 (Adapters & Parsers) - **进度: 90% (全面 AI 增强)**
目标：消除网络依赖，确保解析逻辑在离线状态下 100% 可靠。

| 子模块 | 覆盖率 | 关键测试点 | 状态 |
| :--- | :--- | :--- | :--- |
| Bilibili | 77% | 视频、文章、动态 Mock 解析 | ✅ 已完成 |
| Universal | **70%** | **AI 提取 Layer 1/2 异步链路、离线编排** | ✅ 已完成 |
| ContentAgent | **71%** | **AsyncOpenAI 升级、结构化扫描、脏 MD 清洗** | ✅ 已完成 |
| Zhihu/Weibo/X | ~65% | 多态 JSON 样本注入测试 | ✅ 已完成 |

### 2. 核心基础设施 (Core Infrastructure) - **进度: 85%**
目标：验证系统的“神经系统”和任务分发的绝对可靠性。

| 子模块 | 覆盖率 | 关键测试点 | 状态 |
| :--- | :--- | :--- | :--- |
| EventBus | **76%** | **SSE 心跳、订阅者溢出清理、Outbox 跨实例同步** | ✅ 已完成 |
| QueueAdapter | **76%** | **并发吞吐基准 (90+ tps)、任务重试隔离** | ✅ 已完成 |
| ContentRepo | **83%** | **SQLite FTS5 降级、JSON 标签过滤、分页边界** | ✅ 已完成 |

### 3. 业务逻辑与机器人 (Services & Bot) - **进度: 60%**
目标：确保业务状态流转的原子性及交互安全性。

| 子模块 | 覆盖率 | 关键测试点 | 状态 |
| :--- | :--- | :--- | :--- |
| ContentService | **52%** | **高并发 IntegrityError 冲突自愈、标签增量合并** | ✅ 已完成 |
| Bot Callbacks | **59%** | **按钮回调权限拦截、消息自动清理、API 转发** | ✅ 已完成 |
| Permissions | 30% | 动态权限管理器校验 | ⏳ 待深化 |

---

## ✅ 已完成里程碑 (Milestones)

- **[2026-03-05] P0: 核心加固与并发自愈 (里程碑级突破)**
  - **并发去重革命**：通过“双 Session 真冲突”测试，验证并加固了 `ContentService` 在极端竞态下的数据合并与自愈能力。
  - **AI 链路异步化**：全量重构 `ContentAgent` 为 `AsyncOpenAI`，并补全 Layer 1 (边界识别) 与 Layer 2 (元数据清洗) 的实战 Mock。
  - **基础设施高覆盖**：EventBus、Queue、Repository 三大支柱模块实现从 <20% 到 >75% 的跨越式增长。
- **[2026-03-04] P0: 消除网络隔离**
  - 建立 `tests/data` 真实样本库，实现 100% 离线运行。

---

## 🚀 后续实施计划（2026-03-05 制定）

当前总覆盖率 **53%**，目标分阶段提升至 **72%+**。

### 🔴 Phase 1: 核心业务逻辑（目标 53% → 60%）

| # | 模块 | 当前 | 目标 | 测试文件 | 关键测试点 | 状态 |
|---|---|---|---|---|---|---|
| 1.1 | `services/distribution/scheduler.py` | 15% → **86%** | 75%+ | `test_distribution_scheduler.py` | `compute_auto_scheduled_at` 限流排期、`enqueue_content` 资格检查/规则匹配/去重/force 重置、`mark_historical_*` 回填 | ✅ |
| 1.2 | `services/distribution/engine.py` | 33% → **90%** | 80%+ | `test_distribution_engine.py` | `match_rules` 规则过滤、`auto_approve_if_eligible` 自动审批+触发入队、`refresh_queue_by_rules` 状态翻转 | ✅ |
| 1.3 | `services/content_service.py` | 49% → **86%** | 70%+ | `test_content_service_deep.py` | 补充未覆盖的 CRUD 分支、批量操作、异常路径 | ✅ |
| 1.4 | `tasks/distribution_worker.py` | 46% | 65%+ | `test_distribution_task.py` | Worker 生命周期、批量轮询、重试退避、并发锁 | ⏳ |

### 🟠 Phase 2: 服务与数据层快速收割（目标 60% → 67%）

| # | 模块 | 当前 | 目标 | 测试文件 | 关键测试点 | 状态 |
|---|---|---|---|---|---|---|
| 2.1 | `services/settings_service.py` | 38% → **96%** | 80%+ | `test_settings_service.py` | 缓存命中/穿透、布尔值解析、`set`/`delete`/`load_all` 全流程、Settings 对象同步 | ✅ |
| 2.2 | `services/content_presenter.py` | 43% → **91%** | 85%+ | `test_content_presenter.py` | `local://` URL 转换、rich_payload/context_data 嵌套转换、U+FFFD 清理、layout_type 优先级 | ✅ |
| 2.3 | `services/dashboard_service.py` | 44% → **94%** | 85%+ | `test_dashboard_service.py` | `classify_distribution_status` 全分支、`build_parse_stats`/`build_distribution_stats` 聚合、规则拆分 | ✅ |
| 2.4 | `repositories/system_repository.py` | 38% | 75%+ | `test_repositories_deep.py` | `get_setting`/`upsert_setting`/`delete_setting`/`list_settings` | ⏳ |
| 2.5 | `repositories/bot_repository.py` | 36% | 75%+ | `test_repositories_deep.py` | Bot CRUD、Chat 列表查询 | ⏳ |
| 2.6 | `services/distribution_rule_service.py` | 40% | 70%+ | `test_distribution_rule_service.py` | 规则 CRUD、目标绑定/解绑、级联操作 | ⏳ |

### 🔵 Phase 3: API 路由层（目标 67% → 72%）

| # | 模块 | 当前 | 目标 | 测试文件 | 关键测试点 | 状态 |
|---|---|---|---|---|---|---|
| 3.1 | `routers/distribution_queue.py` | 31% | 60%+ | `test_api/test_distribution_queue_extra.py` | 队列项 CRUD、批量审批、手动推送、状态过滤 | ⏳ |
| 3.2 | `routers/bot_management.py` | 33% | 60%+ | `test_api/test_bot_management.py` | Bot 增删改、Chat 绑定、连接测试 | ⏳ |
| 3.3 | `routers/bot_config.py` | 42% | 65%+ | `test_api/test_bot_config.py` | 配置 CRUD、运行时加载 | ⏳ |
| 3.4 | `routers/events.py` | 24% | 60%+ | `test_api/test_events.py` | SSE 连接、事件订阅 | ⏳ |

### ⚪ Phase 4: 延后项（视情况推进）

| 模块 | 当前 | 备注 |
|---|---|---|
| `bot/main.py` | 11% | Telegram Bot 启动流程，需完整 Mock Bot API |
| `browser_auth_service.py` | 11% | Playwright 浏览器自动化，测试成本高 |
| `tasks/maintenance.py` | 22% | 无限循环保活任务，需控制时间模拟 |
| `core/crawler_config.py` | 19% | 爬虫配置加载，依赖外部文件 |
