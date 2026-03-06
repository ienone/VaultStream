# 🚀 Discovery & Patrol 实现步骤

## Phase 1 (MVP) — 7 Steps, 13 子任务

### Step 1: 数据库模型与迁移 ✅

> 基础层，所有后续步骤依赖此步骤完成。

| # | 子任务 | 涉及文件 | 说明 | 状态 |
|---|--------|----------|------|------|
| 1.1 | 新增枚举 `DiscoveryState` + `DiscoverySourceKind` | `app/models/base.py` | 7 个状态值 + 5 种来源类型 | ✅ |
| 1.2 | `Content` 模型扩展 | `app/models/content.py` | 新增 `discovery_state`, `expire_at`, `promoted_at`, `ai_reason`, `ai_tags` | ✅ |
| 1.3 | 新增 `DiscoverySource` 模型 | `app/models/content.py` | `discovery_sources` 表，统一源配置 | ✅ |
| 1.4 | `BotChat` 模型增强 | `app/models/bot.py` | 新增 `is_monitoring`, `is_push_target` 字段 | ✅ |
| 1.5 | 编写迁移脚本 | `migrations/m23_add_discovery_system.py` | ALTER TABLE + CREATE TABLE | ✅ |

**测试**: `tests/test_discovery_models.py` — 12/12 passed ✅

---

### Step 2: 去重与 URL 规范化 ✅

| # | 子任务 | 涉及文件 | 说明 | 状态 |
|---|--------|----------|------|------|
| 2.1 | URL 规范化工具 | `app/utils/url_utils.py` | 扩写 `normalize_url_for_dedup()`，去除 www/trailing slash/http→https | ✅ |

**测试**: `tests/test_url_normalizer.py` — 12/12 passed ✅

---

### Step 3: RSS 源适配器 ✅

> 从 Horizon 移植，对接 VaultStream 模型。

| # | 子任务 | 涉及文件 | 说明 | 状态 |
|---|--------|----------|------|------|
| 3.1 | 定义适配器基类 | `app/adapters/discovery/base.py` | `BaseDiscoveryScraper` + `DiscoveryItem` dataclass | ✅ |
| 3.2 | 移植 `RSSScraper` | `app/adapters/discovery/rss.py` | `RSSDiscoveryScraper`，支持 RSS/Atom + 增量 cursor | ✅ |

**测试**: `tests/test_adapters/test_rss_scraper.py` — 7/7 passed ✅

---

### Step 4: Telegram Bot 监听增强 ✅

| # | 子任务 | 涉及文件 | 说明 | 状态 |
|---|--------|----------|------|------|
| 4.1 | `MessageHandler` 链接提取钩子 | `app/bot/monitoring.py` + `app/bot/main.py` | 识别群组消息中的 URL，`is_monitoring=True` 时入库发现流 | ✅ |

**测试**: `tests/test_bot/test_monitoring_hook.py` — 13/13 passed ✅

---

### Step 5: Patrol Service (AI 评分) ✅

| # | 子任务 | 涉及文件 | 说明 | 状态 |
|---|--------|----------|------|------|
| 5.1 | `PatrolService` 实现 | `app/services/patrol_service.py` | `score_item()` / `score_batch()` / `score_pending()` + JSON Mode | ✅ |

**测试**: `tests/test_patrol_service.py` — 16/16 passed ✅

---

### Step 6: API 路由 + Schemas ✅

| # | 子任务 | 涉及文件 | 说明 | 状态 |
|---|--------|----------|------|------|
| 6.1 | Pydantic Schemas | `app/schemas/discovery.py` | Discovery items/sources/settings 请求/响应模型 | ✅ |
| 6.2 | Discovery Router | `app/routers/discovery.py` | §4.1~§4.5 共 13 个端点 | ✅ |
| 6.3 | 注册路由 | `app/main.py` | `include_router(discovery.router)` | ✅ |

**测试**: `tests/test_api/test_discovery_api.py` — 10/10 passed ✅

---

### Step 7: 后台任务 ✅

| # | 子任务 | 涉及文件 | 说明 | 状态 |
|---|--------|----------|------|------|
| 7.1 | `discovery_sync` 任务 | `app/tasks/discovery_sync.py` | 定时遍历启用 sources，调用 scraper + 入库 + 触发评分 | ✅ |
| 7.2 | `discovery_cleanup` 任务 | `app/tasks/discovery_cleanup.py` | 每 6 小时清理 expired/ignored 内容 | ✅ |
| 7.3 | 注册到 lifespan | `app/tasks/__init__.py` + `app/main.py` | 启动时创建异步任务 | ✅ |

**测试**: `tests/test_tasks/test_discovery_tasks.py` — 7/7 passed ✅

---

## 🧪 测试总览

| 优先级 | 测试文件 | 覆盖 Step |
|--------|----------|-----------|
| P0 | `tests/test_discovery_models.py` | Step 1 |
| P0 | `tests/test_url_normalizer.py` | Step 2 |
| P1 | `tests/test_adapters/test_rss_scraper.py` | Step 3 |
| P1 | `tests/test_patrol_service.py` | Step 5 |
| P1 | `tests/test_api/test_discovery_api.py` | Step 6 |
| P2 | `tests/test_bot/test_monitoring_hook.py` | Step 4 |
| P2 | `tests/test_tasks/test_discovery_tasks.py` | Step 7 |
| P2 | `tests/test_discovery_integration.py` | 端到端集成 |

### 测试策略
- **LLM 调用全部 mock**：PatrolService 用固定 JSON 响应
- **RSS/HTTP 全部 mock**：`respx` 或 fixture 文件模拟 feed
- **复用现有 `conftest.py`** 的 `db_session` / `client` fixture
- **每完成一个 Step 立即编写对应测试**

## 实施顺序

```
Step 1 → Step 2 → Step 3 → Step 5 → Step 6 → Step 4 → Step 7
                                      ↑ 可与 Step 4/7 并行
```
