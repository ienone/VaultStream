# 🚀 VaultStream 发现与巡逻系统 (Discovery & Patrol) 集成设计文档

## 1. 概述 (Overview)
为了保持主收藏库的"高意图"与"高纯净度"，系统引入 **"发现缓冲区 (Discovery Buffer)"** 概念。所有自动化来源（RSS、HackerNews、Reddit、GitHub、Telegram 公开频道爬取、Bot 群组监听）的内容将首先进入缓冲区，由 **AI 巡逻 Agent** 进行评分、去重与富化。用户通过"探索"界面进行高效分拣，一键收藏至主库或忽略。

### 1.1 集成范围 (Scope)

源自 Horizon 项目的完整能力清单，按阶段规划：

| 阶段 | 能力 | 说明 |
| :--- | :--- | :--- |
| **Phase 1** | RSS/Atom 订阅 | `feedparser` 提取 + 现有适配器深层解析 |
| **Phase 1** | Telegram Bot 群组监听 | Bot `on_message` 钩子提取链接 |
| **Phase 1** | AI 评分 (Patrol Agent) | 0-10 打分、摘要、标签 |
| **Phase 1** | 跨源 URL 去重 | 规范化 URL 指纹，发现重复则跳过 |
| **Phase 1** | 发现缓冲区 UI + 管理 API | 列表/收藏/忽略/批量操作 |
| **Phase 2** | HackerNews 聚合 | Top stories + 评论抓取 |
| **Phase 2** | Reddit 聚合 | Subreddit/User 帖子 + 评论 |
| **Phase 2** | GitHub 事件/Release | 用户事件 + 仓库 Release |
| **Phase 2** | Telegram 公开频道爬取 | Web preview 方式抓取（无需 Bot 加入） |
| **Phase 2** | AI 富化 (Enrichment) | 概念提取 → Web 搜索 → 背景知识生成 |
| **Phase 2** | 主题级去重与复杂合并 | 标题 Token Jaccard 相似度合并与正文综合生成 |
| **Phase 3** | 每日摘要 (Daily Summary) | 定时生成 Markdown 摘要报告 |
| **Phase 3** | 摘要推送 | 邮件订阅 / Bot 推送日报 |

---

## 2. 数据库模型变更 (Database Schema)

### 2.1 `contents` 表扩展

> **注意**：`ai_score` (Float)、`summary` (Text)、`tags` (JSON)、`source_type` (String)、`discovered_at` (DateTime) 已存在于现有模型中，**无需重复添加**。

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `discovery_state` | Enum | 发现缓冲区生命周期状态（见下方状态机）。`null` 表示主库内容（非发现流）。 |
| `expire_at` | DateTime | 自动清理的时间戳。仅发现流内容使用。 |
| `promoted_at` | DateTime | 从缓冲区收藏至主库的时间。 |
| `ai_reason` | Text | AI 评分理由。 |
| `ai_tags` | JSON | AI 自动生成的语义标签（与用户手动 `tags` 字段分离）。 |

#### 发现状态机 (`discovery_state`)

```
ingested → scored → [enriched] → visible → promoted | ignored → expired
                                              ↓
                                          (expire_at 过期后自动清理)
```

| 状态 | 含义 |
| :--- | :--- |
| `ingested` | 刚采集，等待 AI 评分 |
| `scored` | 已评分，低于阈值的自动标记 `ignored` |
| `visible` | 通过阈值，可在探索界面展示 |
| `promoted` | 用户已收藏至主库 |
| `ignored` | 用户手动忽略或低分自动忽略 |
| `merged` | 被合并入另一条内容，不再独立展示 |
| `expired` | 超过保留期限，等待清理任务删除 |

### 2.2 新增 `discovery_sources` 表（通用源配置）

> 替代原设计中的 `rss_sources`，支持所有来源类型的统一管理。

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `id` | Integer (PK) | 唯一标识。 |
| `kind` | Enum | 来源类型：`rss`, `hackernews`, `reddit`, `github`, `telegram_channel` |
| `name` | String | 来源名称（如 "Hacker News Top"、"Simon Willison Blog"）。 |
| `enabled` | Boolean | 是否启用同步。 |
| `config` | JSON | 来源特定配置（如 RSS 的 `url`/`category`；Reddit 的 `subreddit`/`sort`/`min_score`）。 |
| `last_sync_at` | DateTime | 上次成功同步时间。 |
| `last_cursor` | String | 游标/水位线（如最后处理的 entry ID 或时间戳），用于增量抓取。 |
| `last_error` | Text | 最近一次同步错误信息。 |
| `sync_interval_minutes` | Integer | 同步间隔（分钟），默认 60。 |
| `created_at` | DateTime | 创建时间。 |
| `updated_at` | DateTime | 更新时间。 |

**`config` JSON 示例**：

```jsonc
// RSS
{"url": "https://simonwillison.net/atom/everything/", "category": "tech"}

// HackerNews
{"fetch_top_stories": 30, "min_score": 100}

// Reddit
{"subreddit": "MachineLearning", "sort": "hot", "min_score": 10, "fetch_comments": 5}

// GitHub
{"type": "user_events", "username": "torvalds"}

// Telegram 公开频道（web preview 爬取，无需 Bot）
{"channel": "zaihuapd", "fetch_limit": 20}
```

### 2.3 新增 `discovery_settings` 表（用户配置）

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `id` | Integer (PK) | 唯一标识（单例行）。 |
| `interest_profile` | Text | 自然语言描述的用户兴趣画像，供 AI 评分使用。 |
| `score_threshold` | Float | AI 评分过滤阈值（默认 6.0）。 |
| `retention_days` | Integer | 发现流内容保留天数（默认 7）。 |
| `enrichment_enabled` | Boolean | 是否启用 AI 富化（Web 搜索 + 背景生成）。 |
| `daily_summary_enabled` | Boolean | 是否生成每日摘要。 |
| `daily_summary_languages` | JSON | 摘要语言列表（如 `["zh", "en"]`）。 |
| `updated_at` | DateTime | 更新时间。 |

> 或复用现有 `system_settings` 表，以 key-value 方式存储上述配置。

### 2.4 `bot_chats` 表增强

> **不重命名** 现有 `enabled` 字段，在此基础上新增字段。

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `is_monitoring` | Boolean | **[新增]** 是否监听该群组消息并投喂给发现流。 |
| `is_push_target` | Boolean | **[新增]** 是否作为推送目标（与现有 `enabled` 语义互补，`enabled=true` 表示记录活跃可用）。 |

### 2.5 事件级聚合与溯源 (Event-Level Aggregation)

> **核心目标**：解决“同一事件被不同来源以不同维度报道”的信息过载问题。系统将根据内容相似度，将指向同一事件的多个来源动态聚合。

- **逻辑概述**：系统默认以独立卡片展示。仅当 AI 命中聚类或用户手动操作时，才演变为聚合形态。
- **存储方案**：基于 `parent_id` 的递归树状结构，配合增量综述算法节约 Token。
- **详细设计与 UI 规范**：请参阅专项文档 [DISCOVERY_EVENT_AGGREGATION.md](./DISCOVERY_EVENT_AGGREGATION.md)。

---

## 3. 后端架构设计 (Backend Logic)

### 3.1 采集管线 (Ingestion Pipeline)

```
discovery_source → Scraper → URL 规范化/去重 → 入库 (ingested)
       ↓                                              ↓
  (各源适配器)                                    AI 评分 (scored)
                                                      ↓
                                              阈值过滤 → visible / ignored
                                                      ↓
                                             [可选] AI 富化 (enriched)
                                                      ↓
                                               用户操作 → promoted / ignored
```

**关键设计决策**：
- **去重先于 AI**：URL 规范化和跨源去重在 AI 评分之前完成，避免浪费 LLM 配额。
- **轻量入库**：非 URL 类内容（如 Reddit self-post、GitHub release notes、HN Ask/Show）直接以 title/body 入库，不需要深层适配器解析。
- **深层解析可选**：仅对有外链的发现项调用现有 `UniversalAdapter` 或专用解析器。

### 3.2 源适配器 (Source Scrapers)

从 Horizon 移植以下适配器至 `app/adapters/discovery/`：

| 适配器 | 源文件 | 说明 |
| :--- | :--- | :--- |
| `RSSScraper` | `scrapers/rss.py` | feedparser 解析，支持环境变量 URL 模板 |
| `HackerNewsScraper` | `scrapers/hackernews.py` | Firebase API，含评论抓取 |
| `RedditScraper` | `scrapers/reddit.py` | JSON API，含 subreddit/user/评论 |
| `GitHubScraper` | `scrapers/github.py` | REST API，用户事件 + Release |
| `TelegramChannelScraper` | `scrapers/telegram.py` | Web preview 公开频道爬取（仅用于 Bot 未加入的公开频道） |

#### Telegram 采集策略（双模式统一）

Telegram 频道并非全部公开，但 Bot 可被邀请加入频道（作为管理员）。系统支持两种采集模式，并**自动选择最优方式**：

| | Bot 监听 (`MessageHandler`) | Web Preview 爬取 (`t.me/s/`) |
| :--- | :--- | :--- |
| **适用** | Bot 已加入的群组/频道（含私有） | Bot 未加入的公开频道 |
| **实时性** | 实时（被动接收推送） | 定时轮询 |
| **资源消耗** | 极低 | 较高（HTTP + HTML 解析 + 反爬限流风险） |
| **数据丰富度** | 完整消息对象（entities、reply、media） | 仅 HTML 文本 + 有限元数据 |

**选择逻辑**：
1. 若目标频道/群组存在于 `bot_chats` 且 `is_monitoring=true` → **Bot 监听**（优先，零成本实时）
2. 若目标为公开频道且 Bot 未加入 → **Web Preview 爬取**（通过 `discovery_sources` 配置 `kind=telegram_channel`）
3. 前端统一展示为"Telegram 来源"，用户无需关心底层采集方式

### 3.3 AI Agent 架构（与现有 Agent 的分层协作）

VaultStream 已有两个 LLM 管线，Patrol Agent **不应与之合并**，而是作为独立层协作：

```
┌─────────────────────────────────────────────────────────────┐
│                    VaultStream AI 管线全景                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─── 主库管线（用户主动提交） ───────────────────────────┐   │
│  │                                                       │   │
│  │  Content Agent (content_agent.py)                     │   │
│  │    Layer 1: 结构扫描 (HTML 边界识别)                    │   │
│  │    Layer 2: 元数据提取 + 正文清洗                      │   │
│  │    → 输出: cleaned_markdown, common_fields, tags      │   │
│  │                                                       │   │
│  │  Summary Service (content_summary_service.py)         │   │
│  │    Vision LLM: 图片描述提取                            │   │
│  │    Text LLM: 精简摘要生成 (≤120字)                     │   │
│  │                                                       │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─── 发现管线（自动化采集） ────────────────────────────┐   │
│  │                                                       │   │
│  │  Patrol Agent (patrol_service.py)         [新增]      │   │
│  │    评分: 0-10 契合度打分 + 理由                        │   │
│  │    摘要: 一句话精简摘要                                │   │
│  │    标签: 语义标签自动提取                              │   │
│  │                                                       │   │
│  │  Enrichment Agent (enrichment_service.py) [Phase 2]   │   │
│  │    概念提取: AI 识别需解释的术语                       │   │
│  │    Web 搜索: DuckDuckGo 背景资料检索                  │   │
│  │    背景生成: 双语结构化分析                            │   │
│  │                                                       │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─── 共享基础设施 ─────────────────────────────────────┐   │
│  │  LLMFactory (llm_factory.py) — 统一模型管理           │   │
│  │    text_llm: 文本任务 (评分/摘要/清洗)                │   │
│  │    vision_llm: 视觉任务 (图片描述/Browser Use)        │   │
│  └───────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

#### 不合并的理由

| 维度 | Content Agent (主库) | Patrol Agent (发现流) |
| :--- | :--- | :--- |
| **触发方式** | 用户提交 URL → 队列任务 | 定时同步 → 批量处理 |
| **输入形态** | 完整 HTML/Markdown 网页 | 轻量元数据（标题+摘要+来源） |
| **LLM 目标** | 结构识别 + 字段提取 + 正文清洗 | 价值评估 + 兴趣匹配 |
| **Token 预算** | 高（2-3 次 LLM 调用/项） | 低（1 次调用/项，批量） |
| **失败容忍度** | 低（用户等待结果） | 高（静默跳过，不影响体验） |

**关键差异**：Content Agent 处理的是用户已确认想要存档的内容，需要精细清洗；Patrol Agent 处理的是海量候选项，需要快速筛选，大部分会被丢弃。合并会导致两边都难以优化。

#### Patrol Agent 详细设计 (`app/services/patrol_service.py`)

```python
class PatrolService:
    """AI 巡逻评分服务"""

    async def score_item(self, content: Content) -> ScoringResult:
        """
        对单条发现内容进行 AI 评分。

        输入: 标题 + 正文(截断) + 来源元数据 + 用户兴趣画像
        输出: { score, reason, summary, tags }
        """

    async def score_batch(self, items: list[Content], batch_size=10):
        """批量评分，串行调用避免 rate limit"""

    def _build_scoring_prompt(self, content, interest_profile) -> tuple[str, str]:
        """
        构建评分 prompt。
        - system: Horizon 的 CONTENT_ANALYSIS_SYSTEM（通用评分标准）
                  + 用户兴趣画像注入（个性化偏好）
        - user: 标题/来源/正文/互动数据
        """
```

**与 LLMFactory 的对接**：
- Patrol Agent 使用 `LLMFactory.get_text_llm()` 获取模型，**复用已有配置**，无需新增 API Key 配置项
- Horizon 原有的多 provider 支持（Anthropic/OpenAI/Gemini/Doubao）由 VaultStream 的 OpenAI-compatible 接口统一覆盖（`ChatOpenAICompatible` 已支持任意 base_url）

#### Enrichment Agent 详细设计 *(Phase 2, `app/services/enrichment_service.py`)*

```python
class EnrichmentService:
    """AI 富化服务 — 为高分内容添加背景知识"""

    async def enrich_item(self, content: Content):
        """
        三步富化管线：
        1. concept_extraction: AI 识别需解释的概念/术语 → 1-3 个搜索 query
        2. web_search: DuckDuckGo 搜索每个 query → 背景资料
        3. background_generation: AI 基于搜索结果生成结构化分析

        结果存储至 content.context_data["enrichment"]:
        {
            "concepts": ["WebTransport", "QUIC"],
            "search_results": [...],
            "background_zh": "...",
            "background_en": "...",
            "community_discussion_zh": "...",
            "sources": [{"url": "...", "title": "..."}]
        }
        """
```

#### Content Agent 与 Patrol Agent 的交汇点

当用户将发现项 **promote** 至主库时，可选择是否触发 Content Agent 深层处理：

```
用户点击"收藏" → discovery_state = promoted
  ↓
判断内容完整度:
  ├── [已有完整正文 body] → 仅生成 Summary（调用 Summary Service）
  └── [仅有标题/摘要，无正文] → 调用 Content Agent 深层解析原始 URL
        → HTML→Markdown → Layer1 → Layer2 → 元数据提取 → Summary
```

这样 Patrol Agent 的轻量评分与 Content Agent 的精细清洗在 promote 环节自然衔接——发现阶段只做快速评分不浪费预算，存档阶段按需深层处理保证主库质量。

### 3.4 去重与事件聚类策略 (Dedup & Clustering)

1.  **URL 去重**（Phase 1）：通过 `canonical_url` 精确去重，重复者追加记录至 `source_links`。
2.  **事件聚类**（Phase 2）：基于相似度计算触发综述生成。具体实现见 [DISCOVERY_EVENT_AGGREGATION.md](./DISCOVERY_EVENT_AGGREGATION.md)。

### 3.5 自动化任务 (Background Tasks)

| 任务 | 触发方式 | 说明 |
| :--- | :--- | :--- |
| `sync_discovery_sources` | 定时（按各源 `sync_interval_minutes`） | 遍历启用的 `discovery_sources`，调用对应 Scraper |
| `score_pending_items` | 事件驱动（新内容入库后） | 对 `ingested` 状态的内容执行 AI 评分 |
| `enrich_visible_items` | 定时/事件驱动 | 对 `visible` 且 `enrichment_enabled` 的内容执行富化 |
| `discovery_cleanup` | 每日凌晨 | 清理 `expire_at` 过期 或 `ignored` 超过保留期的内容 |
| `tg_message_handler` | 实时（Bot webhook） | 处理监听群组中的链接消息 |
| `generate_daily_summary` | 每日定时 *(Phase 3)* | 生成当日高分内容摘要 |

---

## 4. API 端点设计 (API Endpoints)

### 4.1 探索流 (Discovery Items)

| 方法 | 路径 | 说明 |
| :--- | :--- | :--- |
| `GET` | `/v1/discovery/items` | 列出缓冲区内容（分页、排序、过滤） |
| `GET` | `/v1/discovery/items/{id}` | 获取单条发现内容详情 |
| `PATCH` | `/v1/discovery/items/{id}` | 更新状态（`promoted` / `ignored`） |
| `POST` | `/v1/discovery/items/bulk-action` | 批量操作（批量收藏/忽略） |
| `GET` | `/v1/discovery/stats` | 统计信息（各状态数量、来源分布、评分分布） |

**`GET /v1/discovery/items` 查询参数**：
```
?page=1&page_size=20
&sort_by=ai_score|discovered_at    # 排序字段
&sort_order=desc|asc
&state=visible|ignored|promoted     # 发现状态过滤
&source_kind=rss|hackernews|reddit  # 来源类型
&source_id=3                        # 特定来源
&score_min=6.0                      # 最低分数
&score_max=10.0
&tags=tech,ai                       # AI 标签过滤
&q=keyword                          # 关键词搜索
&date_from=2026-03-01
&date_to=2026-03-06
```

**`PATCH /v1/discovery/items/{id}` 请求体**：
```json
{ "state": "promoted" }
// 或
{ "state": "ignored" }
```

**`POST /v1/discovery/items/bulk-action` 请求体**：
```json
{
  "ids": [1, 2, 3],
  "action": "promote" | "ignore"
}
```

### 4.2 聚合组管理 (Merge / Split)

| 方法 | 路径 | 说明 |
| :--- | :--- | :--- |
| `POST` | `/v1/discovery/items/merge` | 手动合并多个发现项为一组 |
| `POST` | `/v1/discovery/items/{id}/split` | 从聚合组中拆出一个来源为独立项 |
| `GET` | `/v1/discovery/items/{id}/sources` | 获取某条内容的所有来源溯源记录 |

**合并请求**：
```json
{
  "primary_id": 10,
  "merge_ids": [12, 15]
}
```
- `primary_id` 作为主记录保留，`merge_ids` 的内容/元数据合并入主记录
- 被合并的 content 记录标记为 `merged`（新增一个 discovery_state 值），不再独立展示
- 各被合并项的原始信息转存为 `content_discoveries` 记录

**拆出请求**：
```json
{
  "discovery_id": 5
}
```
- 将 `content_discoveries` 中 id=5 的记录拆出，创建独立的 `content` 记录
- 拆出后原聚合组重新计算合并字段（标题/分数等）

### 4.3 批量处理与结构化转存 (Bulk Processing)

> 发现流中大量资讯的批量处理和结构化转存，需要专门的 API 支持。

| 方法 | 路径 | 说明 |
| :--- | :--- | :--- |
| `POST` | `/v1/discovery/items/bulk-promote` | 批量收藏（含按条件筛选的全量操作） |
| `POST` | `/v1/discovery/items/bulk-ignore` | 批量忽略 |
| `POST` | `/v1/discovery/items/bulk-enrich` | 批量触发 AI 富化 |
| `POST` | `/v1/discovery/items/bulk-rescore` | 批量重新评分（画像修改后） |
| `DELETE` | `/v1/discovery/items/expired` | 清理所有已过期项 |

**按条件批量操作（无需逐条选中）**：
```json
{
  "action": "promote",
  "filter": {
    "score_min": 8.0,
    "source_kind": "hackernews",
    "date_from": "2026-03-05"
  },
  "limit": 50
}
```

**批量 promote 时的结构化转存流程**：

```
批量 promote 请求
  ↓
1. 筛选符合条件的 visible 项
  ↓
2. 逐项执行 promote 逻辑:
   ├── discovery_state → promoted
   ├── 写入 context_data["source_links"]
   ├── ai_tags 合并至 tags
   └── 判断是否需要深层解析:
       ├── [有完整 body] → 仅调用 Summary Service
       └── [仅有标题/摘要] → 入队 Content Agent 解析任务
  ↓
3. 触发分发规则匹配（复用现有分发引擎）
  ↓
4. 返回 { promoted_count, enqueued_for_parsing, errors }
```

**实现便利性分析**：
- ✅ 已有 `BatchReviewRequest` 模式可参考（`content_ids` + `action`）
- ✅ 已有 `TaskWorker` 队列可承接按需的 Content Agent 解析任务
- ✅ `context_data` JSON 字段无需 migration，直接写入
- ⚠️ 批量操作需注意 SQLite 事务大小：建议每批 ≤ 100 条，大批量分页提交
- ⚠️ 批量 AI 评分/富化是异步后台任务，API 返回任务 ID，前端轮询进度

### 4.4 来源管理 (Discovery Sources)

| 方法 | 路径 | 说明 |
| :--- | :--- | :--- |
| `GET` | `/v1/discovery/sources` | 列出所有来源（支持 `kind` 过滤） |
| `POST` | `/v1/discovery/sources` | 新增来源 |
| `GET` | `/v1/discovery/sources/{id}` | 获取来源详情 |
| `PUT` | `/v1/discovery/sources/{id}` | 修改来源配置 |
| `DELETE` | `/v1/discovery/sources/{id}` | 删除来源 |
| `POST` | `/v1/discovery/sources/{id}/sync` | 手动触发同步 |
| `GET` | `/v1/discovery/sources/{id}/status` | 查看同步状态 |

**新增来源请求体示例**：
```json
{
  "kind": "rss",
  "name": "Simon Willison's Blog",
  "enabled": true,
  "config": {
    "url": "https://simonwillison.net/atom/everything/",
    "category": "tech"
  },
  "sync_interval_minutes": 60
}
```

### 4.5 发现设置 (Discovery Settings)

| 方法 | 路径 | 说明 |
| :--- | :--- | :--- |
| `GET` | `/v1/discovery/settings` | 获取发现系统配置 |
| `PATCH` | `/v1/discovery/settings` | 更新配置 |

**响应/请求体**：
```json
{
  "interest_profile": "对 AI/ML、系统架构、开源工具感兴趣",
  "score_threshold": 6.0,
  "retention_days": 7,
  "enrichment_enabled": false,
  "daily_summary_enabled": false,
  "daily_summary_languages": ["zh"]
}
```

### 4.6 Telegram Bot 群组管理（增强）

| 方法 | 路径 | 说明 |
| :--- | :--- | :--- |
| `GET` | `/v1/bot/chats` | 列出群组（已有，确认支持 `bot_config_id` 过滤） |
| `POST` | `/v1/bot/sync-chats` | 刷新群组列表（需指定 `bot_config_id`） |
| `PATCH` | `/v1/bot/chats/{id}` | 更新 `is_monitoring` / `is_push_target` 开关 |

> 注意：已有的 `bot_management.py` 路由中可能已实现部分端点，需检查并增强。

### 4.7 每日摘要 *(Phase 3)*

| 方法 | 路径 | 说明 |
| :--- | :--- | :--- |
| `POST` | `/v1/discovery/summaries/generate` | 手动触发生成当日摘要 |
| `GET` | `/v1/discovery/summaries` | 列出已生成的摘要（分页） |
| `GET` | `/v1/discovery/summaries/{id}` | 获取摘要详情（Markdown） |

---

## 5. 前端设计方案 (Frontend UI/UX)

### 5.1 探索界面 (Discovery Page)
*   **交互形态**：支持“独立”与“聚合”双态呈现。聚合态采用树状折叠样式与拖拽交互。
*   **详细设计规范**：关于聚合组的展开逻辑、拖拽合并/拆分交互，请参阅专项文档 [DISCOVERY_EVENT_AGGREGATION.md](./DISCOVERY_EVENT_AGGREGATION.md) §2。
*   **通用交互**：
    *   **横屏布局**：左侧 Master 列表（超窄卡片），右侧 Detail 详情。
    *   **竖屏布局**：单列卡片流，点击进入详情。
    *   **批量操作**：长按多选 → 批量收藏/忽略。
    *   **筛选栏**：来源类型、分数范围、AI 标签快速过滤。

### 5.2 统一设置中心 (Settings Expansion)
将原有的 Bot 配置从审阅界面移动至设置页，形成"集成中心"：

1.  **AI 巡逻配置**：
    *   **用户画像输入框**：自然语言描述喜好。
    *   **分数阈值滑块**：0-10 过滤线。
    *   **清理时限选择**：3/7/15天。
2.  **来源管理**：统一列表展示所有 `discovery_sources`，支持 CRUD + 手动同步按钮。按 `kind` 分组展示。
3.  **Telegram 监听配置**：
    *   表格列出所有群组。
    *   两个独立开关：**"巡逻监听"** (`is_monitoring`) 与 **"分发推送"** (`is_push_target`)。

---

## 6. 核心逻辑合并路径

### Phase 1（MVP）
1.  **Migration**：应用数据库迁移 —— `contents` 增加 `discovery_state`/`expire_at`/`promoted_at`/`ai_reason`/`ai_tags`；新建 `discovery_sources`；`bot_chats` 增加 `is_monitoring`/`is_push_target`。
2.  **Source Scrapers**：从 Horizon 移植 `RSSScraper` 至 `app/adapters/discovery/rss.py`。
3.  **Bot Enhancement**：修改 `app/bot/main.py`，增加 `MessageHandler` 链接识别钩子，提取 URL 后走采集管线入库。
4.  **Patrol Service**：实现 `app/services/patrol_service.py`，对接已有 LLM 配置，执行 JSON Mode 评分。
5.  **Discovery Router**：新建 `app/routers/discovery.py`，实现 items + sources + settings 端点。
6.  **Background Tasks**：在 `app/tasks/` 中新增 `discovery_sync.py` 和 `discovery_cleanup.py`。
7.  **Frontend**：Flutter 新增 `Discovery` 模块，重构 `Settings` 页面。

### Phase 2（富化 + 多源）
1.  移植 HackerNews / Reddit / GitHub / Telegram 公开频道适配器。
2.  实现 AI 富化管线（概念提取 → Web 搜索 → 背景生成）。
3.  实现主题级去重。
4.  新增 `content_discoveries` 溯源表。

### Phase 3（摘要 + 推送）
1.  移植 DailySummarizer，实现每日摘要生成。
2.  摘要推送（邮件 / Bot 消息）。

---

## 7. 技术注意事项

### 7.1 Platform 枚举兼容性
现有 `Platform` 枚举不包含 `hackernews`、`reddit`、`github` 等值。发现流内容统一使用 `platform = "universal"`，通过 `source_type` 字段区分实际来源（如 `"rss"`、`"hackernews"` 等）。

### 7.2 SQLite 并发
发现系统引入多个后台任务（定时同步、AI 评分、清理），需注意：
- 使用短事务，避免长时间持锁。
- 同步任务串行执行或有限并发（建议同一时刻最多一个源在同步）。
- 幂等 upsert：基于 `canonical_url` 去重，重复入库时更新而非插入。

### 7.3 收藏至主库的行为定义
用户将发现项 "promote" 至主库时：
- `discovery_state` → `promoted`，`promoted_at` 设为当前时间
- `source_type` 保留为原始来源标识
- `review_status` → 根据分发规则决定（`auto_approved` 或 `pending`）
- AI 标签合并至 `tags`
- 触发分发规则匹配（复用现有分发引擎）

### 7.4 忽略行为
- `ignored` 是软状态，内容不删除
- 防止同一 URL 被重复发现：入库前检查 `canonical_url` 是否已存在且为 `ignored` 状态 → 跳过
- 过期清理任务最终硬删除 `expired` 状态的内容
