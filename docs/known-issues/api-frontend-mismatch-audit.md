# API–前端衔接审计：数据冗余与性能问题

## 状态：修复中

## 审计时间：2026-03-09

## 问题清单

### 1. `GET /contents` 列表返回完整 ContentDetail

**严重度**：低（当前无前端消费者）

**问题**：`/contents` 列表 API 的 `response_model` 为 `ContentListResponse`，其中 `items: List[ContentDetail]` 包含 `body`、`rich_payload`、`context_data`、`extra_stats`、`media_urls` 等重字段。前端收藏库列表实际使用 `/cards` 端点（精简版 `ShareCard`），`/contents` 仅作为管理/调试接口存在。

**已有但未使用的精简 schema**：`ContentListItem` 和 `ContentListItemResponse` 已在 `schemas/content.py` 中定义，但 router 未引用。

**修复方案**：将 `GET /contents` 的 response_model 改为 `ContentListItemResponse`，序列化使用 `ContentListItem`。

**涉及文件**：
- `backend/app/routers/contents.py` — `list_contents()`
- `backend/app/schemas/content.py` — `ContentListItem`, `ContentListItemResponse`

---

### 2. `GET /distribution-queue/items` 嵌套对象从未填充

**严重度**：低（冗余字段，不影响性能）

**问题**：`ContentQueueItemResponse` schema 定义了三个嵌套关联对象：
- `content: Optional[ContentListItem]`
- `rule: Optional[DistributionRuleResponse]`
- `bot_chat: Optional[BotChatResponse]`

后端 `_to_queue_item_response()` 构建响应时**从未填充**这三个字段（始终为 null），实际 title/tags/cover_url 等已平铺到顶层。前端 `QueueItem` 模型也只读平铺字段。

**修复方案**：从 `ContentQueueItemResponse` 中移除三个嵌套字段。

**涉及文件**：
- `backend/app/schemas/queue.py` — `ContentQueueItemResponse`

---

### 3. `GET /targets` 全量加载 PushedRecord 有性能风险

**严重度**：中（数据增长后会变慢）

**问题**：`list_all_targets()` 中通过 `select(PushedRecord).where(target_id.in_(ids))` 加载**所有**推送记录到内存，然后在 Python 层统计。随着推送记录增长（数千→数万条），此查询会成为慢查询并消耗大量内存。

**修复方案**：改用 SQL 聚合查询 `SELECT target_id, COUNT(*), MAX(pushed_at) FROM pushed_records GROUP BY target_id`，避免加载完整 ORM 对象。

**涉及文件**：
- `backend/app/routers/distribution.py` — `list_all_targets()`

---

### 4. `GET /dashboard/stats` 每次请求遍历文件系统

**严重度**：中（IO 密集）

**问题**：`get_dashboard_stats()` 每次请求都通过 `os.walk()` 遍历整个存储目录计算磁盘用量。当存储文件数量增长到数千个后，此操作会显著增加响应延迟。

**修复方案**：对 `storage_usage_bytes` 引入内存缓存（TTL 5 分钟），避免每次请求都遍历文件系统。

**涉及文件**：
- `backend/app/routers/system.py` — `get_dashboard_stats()`

---

### 5. `GET /contents` 和 `GET /cards` 共用同一全字段查询

**严重度**：低（SQLite 场景下影响不大）

**问题**：两个不同粒度的 API 端点底层调用同一个 `repo.list_contents()`，执行 `SELECT *` 全字段查询。`/cards` 在 Python 层丢弃多余字段（body、rich_payload 等），浪费了数据库 IO。

**修复方案**：为 `/cards` 创建列投影查询方法 `repo.list_cards()`，只 SELECT 卡片展示所需的列。

**涉及文件**：
- `backend/app/repositories/content_repository.py` — 新增 `list_cards()`
- `backend/app/routers/contents.py` — `list_share_cards()` 调用新方法

---

### 6. Discovery 列表 API 曾返回完整字段

**严重度**：已修复

**问题**：`GET /discovery/items` 使用 `DiscoveryItemResponse`（含 body/rich_payload/media_urls/context_data），而前端 `DiscoveryItemCard` 仅使用 title/coverUrl/aiScore/sourceType/discoveredAt。

**修复方案**：已拆分为 `DiscoveryItemListItem`（列表精简版）和 `DiscoveryItemResponse`（详情完整版），列表 API 已切换为精简 schema。

**涉及文件**：
- `backend/app/schemas/discovery.py` — 新增 `DiscoveryItemListItem`
- `backend/app/routers/discovery.py` — `list_discovery_items()` 使用精简 schema
