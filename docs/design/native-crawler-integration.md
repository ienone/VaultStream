# 智能爬虫与发现层设计方案 (Python Native)

## 概述

本方案作为 OpenClaw 的轻量化替代，旨在利用 Python 原生生态中的先进工具，将 AI 驱动的内容发现和通用解析能力直接集成到 VaultStream 后端。

**核心组件：**
1.  **Browser Use**: 用于 **“主动发现” (Active Discovery)**。它让 LLM (Claude/GPT) 像人类一样操作浏览器（滚动、点击、搜索），非常适合处理动态流（如 Twitter/X 刷推、B站动态）。
2.  **Crawl4AI**: 用于 **“通用解析” (Smart Fallback)**。它是专为 LLM 优化的爬虫，能将任意网页转化为干净的 Markdown，适合处理用户提交的未适配 URL。

---

## 系统架构

移除独立的 Node.js Gateway，所有功能作为 Python Worker 运行在 Backend 内部。

```
┌─────────────────────────────────────────────────────────────────┐
│                    VaultStream Frontend (Flutter)                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │  用户存档列表  │  │  AI 发现流   │  │  主题订阅 & 设置     │   │
│  └──────────────┘  └──────────────┘  └──────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │ HTTP API
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 VaultStream Backend (FastAPI)                    │
│                                                                 │
│  ┌────────────┐  ┌──────────────┐  ┌─────────────────────────┐  │
│  │ URL 路由器  │  │              │  │  Background Workers     │  │
│  └──────┬─────┘  │              │  │ (Celery / Async Task)   │  │
│         │        │              │  │                         │  │
│    已适配?       │  数据持久化   │  │  ┌───────────────────┐  │
│   ┌─────┴─────┐  │ (SQLite/PG)  │  │  │  Discovery Worker │  │
│   ▼           ▼  │              │  │  │  (Browser Use)    │  │
│ 原生Adapter   │  │              │  │  └───────────────────┘  │
│ (Bilibili等)  │  │              │  │  ┌───────────────────┐  │
│               │  │              │  │  │  Universal Parser │  │
│   未适配?     │  │              │  │  │  (Crawl4AI)       │  │
│   ┌───────────┘  │              │  │  └───────────────────┘  │
│   ▼              │              │  └─────────────────────────┘  │
│ GenericAdapter   │              │                               │
│ (调用 Crawl4AI)  │              │                               │
└──────────────────┴──────────────┴───────────────────────────────┘
          │                 │                    ▲
          ▼                 ▼                    │
    ┌───────────┐     ┌───────────┐        ┌───────────┐
    │  Web Page │     │ Database  │        │ LLM API   │
    └───────────┘     └───────────┘        │ (Claude)  │
                                           └───────────┘
```

---

## 核心功能详解

### 功能 1: 智能 Fallback (通用解析)

当用户提交一个 VaultStream 没有原生 Adapter 支持的 URL 时，系统自动调用 `Crawl4AI` 进行通用解析。

**流程：**
1.  用户提交 URL (例如某个人博客文章)。
2.  `URLRouter` 发现无匹配 Adapter，分发给 `GenericAdapter`。
3.  `GenericAdapter` 调用 `Crawl4AI`：
    *   加载页面 (支持 JS 渲染)。
    *   智能提取正文 (去除侧边栏、广告)。
    *   **转换为 Markdown**。
    *   提取图片/视频链接列表。
4.  后端重用现有的 `MediaDownloader` 处理提取出的媒体链接。
5.  入库，`source_type="user_submit"`。

**tips**
*   速度快。
*   格式统一，直接生成易于阅读的 Markdown。
*   要注意适配内容存档需要的字段（标题、作者、封面图、TAG等），未来可结合 LLM 进行后处理。

### 功能 2: AI 主动发现 (Active Discovery)

利用 `Browser Use` 模拟人类浏览行为，定期从各大平台挖掘高价值内容。

**场景举例：自动刷 Twitter**
1.  **Cron 触发**: 每天 20:00。
2.  **启动 Discovery Worker**:
    *   加载 `Browser Use` Agent。
    *   **Prompt**: "登录 Twitter，搜索关键词 'AI Agent' 或 'LLM'。向下滚动浏览，每找到一条点赞数超过 100 且包含技术干货的推文，就提取其链接和摘要。忽略纯广告。浏览 15 分钟。"
3.  **Agent 执行**:
    *   打开浏览器 -> 登录 (使用保存的 Cookies) -> 搜索 -> 滚动 -> 视觉识别/DOM 分析 -> 记录数据。
4.  **结果处理**:
    *   Agent 返回候选列表 `[{url, reason, summary}, ...]`.
    *   后端进行 **去重** (检查数据库是否已存在)。
    *   对新内容调用 `Adapter` (如果是 Twitter 链接则用 TwitterAdapter) 进行完整归档。
    *   入库，`source_type="ai_discovered"`, `ai_score=8.5`。

### 功能 3: 数据清洗与后处理 (Post-Processing Strategy)

针对 Crawl4AI 通用解析可能出现的“过度解析”问题（即抓取到导航栏、侧边栏、广告噪音等），采取以下分层处理策略，**考虑到通用性，不能在没有指定站点的情况下在 GenericAdapter 中硬编码通用的 CSS 选择器**。但后续可能根据具体站点添加特定规则，所以考虑到扩展性，设计时此通用解析器需要是一个文件夹，便于显式解耦。

**策略 A: LLM 语义提取 (默认/推荐)**
利用 LLM 强大的语义理解能力，从嘈杂的 Markdown 中提取核心内容。
*   **输入**: 网页原始 Markdown (包含噪音)。
*   **模型**: 使用低成本模型 (如 Qwen-Turbo, DeepSeek )。
*   **指令**: "分析以下 Markdown 内容，提取主要的正文内容、标题和图片链接。忽略导航菜单、页脚、版权声明和推荐列表。以 JSON 格式返回。"
*   **Schema**:
    ```json
    {
      "title": "...",
      "content": "...",
      "media_urls": ["..."],
      "author": "..."
    }
    ```

**策略 B: 启发式清洗 (备选)**
对于 token 预算受限的场景，使用算法清洗：
*   **Readability 算法**: 优先提取文本密度高的区域。
*   **关键词过滤**: 剔除包含 "Login", "Sign up", "Privacy Policy", "Footer" 等关键词的短文本块。
*   **去重**: 移除在多个页面中重复出现的文本块（通常是导航/页脚）。

### 功能 4: 智能推送与通知 (Intelligent Push & Notification)

推送逻辑将直接由 VaultStream 后端的定时任务模块（Scheduler）驱动，结合现有的 Telegram Bot(后续扩展至其他渠道如QQ的NapCat)功能实现闭环。

**工作流程：**

```
Cron Scheduler (每日 09:00 / 21:00)
         │
         ▼
┌─────────────────────────────────────┐
│  Push Service (Python Worker)       │
│                                     │
│  1. 数据库查询 (Query)               │
│     SELECT * FROM contents          │
│     WHERE source_type = 'ai_discovered'
│       AND ai_score >= 8.0           │
│       AND is_pushed = FALSE         │
│                                     │
│  2. 按主题分组 (Grouping)            │
│     - AI 资讯 (3条)                  │
│     - 独立开发 (2条)                 │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│  LLM 摘要生成 (Summarization)        │
│                                     │
│  Prompt: "你是一个科技编辑。请将以下   │
│  5条 AI 相关新闻汇总成一份简报，包含   │
│  一句话总评和每条新闻的要点摘要。"     │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│  多渠道分发 (Distribution)           │
│                                     │
│  ┌──────────────┐  ┌──────────────┐ │
│  │ Telegram Bot │  │ Webhook      │ │
│  │ (Rich Text)  │  │ (JSON Payload) │ │
│  └──────────────┘  └──────────────┘ │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│  状态更新                            │
│  UPDATE contents SET is_pushed=TRUE │
└─────────────────────────────────────┘
```

**详细设计：**

1.  **筛选策略 (Filtering)**
    *   **高分优先**: 默认只推送 `ai_score > 8.0` 的高质量内容，避免打扰用户。
    *   **去重机制**: 如果同一主题下有多篇相似内容（通过 Vector 相似度或 URL 聚类），只推送最新或分数最高的一篇。

2.  **摘要生成 (Digest Generation)**
    *   利用 LLM 将零散的链接转化为一份结构化的“早报/晚报”。
    *   格式示例：
        > 🌅 **VaultStream 每日精选**
        >
        > **🤖 AI 趋势**
        > 1. [DeepMind 发布新一代模型...] - *核心突破是解决了数学推理问题...*
        > 2. [OpenAI 内部备忘录泄露] - *主要讨论了算力瓶颈...*
        >
        > **🛠️ 开发工具**
        > 1. [Browser-use 发布 v0.1] - *让 AI 操控浏览器的最佳实践...*

3.  **交互式推送 (Interactive Push)**
    *   在 Telegram 消息下方附带按钮：
        *   `[📥 归档到稍后读]` (将状态从 `ai_discovered` 改为用户收藏)
        *   `[❌ 不感兴趣]` (降低该 Topic 权重，删除记录)
        *   `[🔗 查看原文]`

4.  **用户配置**
    *   现已有的配置界面扩展，允许用户自定义发现与推送偏好： 
    *   推送频率：实时 / 每日摘要 / 每周精选。
    *   推送渠道：Telegram / Email / Discord Webhook。
    *   最低分阈值：用户可自定义。

---

## 数据模型 (保持不变)

复用 OpenClaw 方案中设计的数据库变更：

```sql
-- 区分来源
ALTER TABLE contents ADD COLUMN source_type TEXT DEFAULT 'user_submit'; 
-- 评分
ALTER TABLE contents ADD COLUMN ai_score REAL;
-- 发现配置表
CREATE TABLE discover_topics (...);
CREATE TABLE discover_sources (...);
```

---

## 实施计划

### 依赖库

```text
browser-use
crawl4ai
playwright
langchain-anthropic  # 或其他 LLM 接口
```

### 目录结构规划

```
backend/
├── app/
│   ├── adapters/
│   │   └── generic_adapter/    <-- 新增：封装 Crawl4AI
│   ├── services/
│   │   └── discovery/           <-- 新增：发现模块
│   │       ├── __init__.py
│   │       ├── agent.py         <-- 封装 Browser Use
│   │       ├── task_manager.py  <-- 调度任务
│   │       └── prompts.py       <-- 浏览策略 Prompt
```

### 关键配置

无需 Docker 额外部署容器，只需配置环境变量：

```env
# LLM Provider 
ANTHROPIC_API_KEY=sk-...

# Browser Use Settings
BROWSER_USE_HEADLESS=true  # 生产环境无头模式
BROWSER_SAVE_COOKIES=true  # 持久化登录状态
```

---

## 优劣势分析 (对比 OpenClaw)

| 特性 | OpenClaw 方案 | **Python Native (本方案)** |
| :--- | :--- | :--- |
| **架构复杂度** | **高** (需维护 Node.js 服务, HTTP 通信) | **低** (进程内直接调用, 易调试) |
| **自定义能力** | 受限于 OpenClaw API | **无限** (完全控制 Prompt 和浏览器行为) |
| **资源占用** | 中 (Docker 容器) | **低/动态** (按需启动 Playwright 进程) |
| **刷动态流能力**| 弱 (偏向静态抓取) | **强** (Browser Use 专为此设计) |
| **生态融合** | 异构 (JS + Python) | **同构** (全 Python，完美复用现有 Models/DB) |
