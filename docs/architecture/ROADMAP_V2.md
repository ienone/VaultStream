# VaultStream v2 设计文档与路线图

> 本文档涵盖三大核心演进方向：推送系统简化重构、多平台收藏自动导入、大模型深度集成（RAG + Agent）。

---

## 目录

- [0. 术语与约定](#0-术语与约定)
- [1. 推送系统简化重构](#1-推送系统简化重构)
  - [1.1 现状问题分析](#11-现状问题分析)
  - [1.2 目标架构](#12-目标架构)
  - [1.3 数据模型变更](#13-数据模型变更)
  - [1.4 详细设计](#14-详细设计)
  - [1.5 迁移策略](#15-迁移策略)
- [2. 多平台收藏自动导入](#2-多平台收藏自动导入)
  - [2.1 实现策略](#21-实现策略)
  - [2.2 各平台 API 分析](#22-各平台-api-分析)
  - [2.3 架构概览](#23-架构概览)
  - [2.4 详细设计](#24-详细设计)
  - [2.5 风控与限流](#25-风控与限流)
  - [2.6 数据模型](#26-数据模型)
  - [2.7 开源许可合规](#27-开源许可合规)
  - [2.8 前端配置](#28-前端配置)
- [3. 大模型深度集成](#3-大模型深度集成)
  - [3.1 RAG 语义检索](#31-rag-语义检索)
  - [3.2 Agent 系统](#32-agent-系统)
  - [3.3 Tool Using 体系](#33-tool-using-体系)
  - [3.4 自然语言推送](#34-自然语言推送)
  - [3.5 数据模型](#35-数据模型)
- [4. 路线图（Phase 划分）](#4-路线图phase-划分)
- [5. 简历包装建议](#5-简历包装建议)

---

## 0. 术语与约定

| 术语 | 含义 |
|------|------|
| 主库 | `contents` 表中用户主动收藏的内容（`discovery_state IS NULL` 或 `promoted`） |
| 探索流 | `contents` 表中 `discovery_state` 不为空的发现内容 |
| 队列项 | `content_queue_items` 表中的推送任务 |
| 目标 | 一个 (Rule, BotChat) 的推送终点 |
| CLI 桥接 | 通过 subprocess 调用外部 CLI 工具获取数据 |

---

## 1. 推送系统简化重构

### 1.1 现状问题分析

当前推送流水线分散在 5 个模块、3 层判定中：

```
parsing.py → _check_auto_approval
    → engine.py → auto_approve_if_eligible (auto_approve_conditions)
        → enqueue_content_background
            → scheduler.py → enqueue_content
                → engine.match_rules (check_match_conditions) ①
                → evaluate_target_decision (check_match_conditions) ② ← 重复
                    → 创建 ContentQueueItem
                        → distribution_worker.py → _process_item
                            → 资格检查 ③ ← 又一次
```

**量化问题**：

| 问题 | 影响 | 涉及文件 |
|------|------|---------|
| 同一内容的 `check_match_conditions` 被调用 2 次 | 浪费计算 + 逻辑分歧风险 | `engine.py`, `scheduler.py` |
| `auto_approve_conditions` 与 `match_conditions` 语义重叠 | 用户困惑：两种条件的区别是什么？ | `engine.py`, `decision.py` |
| PENDING 队列项（`needs_approval=True`）占用空间 | 队列表膨胀，worker 需额外过滤 | `scheduler.py` |
| 历史回填创建 SKIPPED 记录 | 每绑定一个新目标，全量扫描所有内容写入 SKIPPED | `scheduler.py:333-455` |
| 入队阶段就计算限流排期 | `compute_auto_scheduled_at` 查 2 张表，入队变慢 | `scheduler.py:31-97` |
| Worker 再次做资格检查 + 去重 | 入队时已判定，推送时又判定一次 | `distribution_worker.py:240-275` |

### 1.2 目标架构

```
简化后的推送流水线 (Pipeline v2)
══════════════════════════════════

内容入库 → 解析成功 (PARSE_SUCCESS)
                ↓
        ┌───────────────────┐
        │   审批层（统一）     │
        │                   │
        │  规则 A: 免审批     │ ─→ 自动 APPROVED
        │  规则 B: 需审批     │ ─→ 等人工 → APPROVED
        └───────────────────┘
                ↓
        ┌───────────────────┐
        │   匹配 & 入队       │  ← 仅对 APPROVED 内容触发
        │                   │
        │  遍历 enabled 规则  │
        │  match(content)    │  ← 单一判定函数
        │  去重(PushedRecord)│
        │  写入 SCHEDULED    │  ← 队列中不存在 PENDING 状态
        └───────────────────┘
                ↓
        ┌───────────────────┐
        │   Worker 推送       │
        │                   │
        │  领取 SCHEDULED    │
        │  限流检查(此时计算)  │  ← 排期移到消费侧
        │  push → SUCCESS   │
        └───────────────────┘
```

**核心原则**：

1. **队列只存"确定要推送"的任务** — 不存 PENDING/SKIPPED 占位
2. **判定只做一次** — 统一为 `should_distribute(content, rule, target) → bool`
3. **排期延迟到消费时** — 入队轻量化
4. **历史回填不写记录** — 用 watermark 时间戳标记

### 1.3 数据模型变更

#### DistributionRule 变更

```python
class DistributionRule(Base):
    # --- 保留 ---
    id, name, description, match_conditions, enabled, priority
    nsfw_policy, rate_limit, time_window
    template_id, render_config, created_at, updated_at

    # --- 简化 ---
    approval_required: bool  # 保留，语义不变

    # --- 删除 ---
    # auto_approve_conditions  ← 合并到 approval_required=False
```

**迁移规则**：现有 `auto_approve_conditions` 非空且 `approval_required=True` 的规则 → 拆分为两条规则，或由用户在前端重新确认。

#### ContentQueueItem 状态机简化

```
当前:  PENDING → SCHEDULED → PROCESSING → SUCCESS/FAILED/SKIPPED/CANCELED
简化:  SCHEDULED → PROCESSING → SUCCESS/FAILED
                                    ↓
                              (重试 → SCHEDULED)
```

删除的状态：
- `PENDING` — 不再需要，未审批的内容不入队
- `SKIPPED` — 不再需要，不匹配的内容不入队
- `CANCELED` — 可用 `DELETE` 队列项替代

删除的字段：
- `needs_approval` — 不再需要
- `approved_at` — 不再需要

#### 新增 Watermark 字段

```python
class DistributionTarget(Base):
    # --- 新增 ---
    backfill_watermark: datetime  # 绑定时刻，早于此时间的内容视为"已处理"
```

### 1.4 详细设计

#### 1.4.1 统一判定函数

将 `check_match_conditions` + `evaluate_target_decision` + `check_auto_approve_conditions` 合并为一个：

```python
# services/distribution/decision.py

def should_distribute(
    content: Content,
    rule: DistributionRule,
    bot_chat: BotChat,
) -> DistributionDecision:
    """
    单一入口：判断 content 是否应推送到 (rule, bot_chat) 目标。

    前置条件（调用方保证）：
    - content.status == PARSE_SUCCESS
    - content.review_status in (APPROVED, AUTO_APPROVED)
    - rule.enabled == True
    - bot_chat.enabled == True, bot_chat.is_accessible == True

    Returns:
        DistributionDecision(push=True/False, reason=...)
    """
    conditions = rule.match_conditions or {}

    # 1. 平台匹配
    if conditions.get("platform") and conditions["platform"] != content.platform.value:
        return SKIP("platform_mismatch")

    # 2. 标签排除
    ...

    # 3. 标签要求 (any/all)
    ...

    # 4. NSFW 匹配条件
    ...

    # 5. NSFW 策略 (block / allow / separate_channel)
    if content.is_nsfw:
        nsfw_policy = rule.nsfw_policy or "block"
        if nsfw_policy == "block":
            return SKIP("nsfw_blocked")
        if nsfw_policy == "separate_channel":
            routed = bot_chat.nsfw_chat_id
            if not routed:
                return SKIP("nsfw_no_channel")
            return PUSH(target_id=routed)

    # 6. 通过
    return PUSH(target_id=bot_chat.chat_id)
```

#### 1.4.2 入队流程简化

```python
# services/distribution/scheduler.py

async def enqueue_content(content_id: int, session: AsyncSession) -> int:
    """为已审批内容创建推送队列项"""
    content = await load_content(session, content_id)

    # 前置：仅处理已审批 + 解析成功
    if not is_eligible(content):
        return 0

    rules = await load_enabled_rules(session)
    targets_map = await load_enabled_targets(session, [r.id for r in rules])

    # 批量查询已有队列项 + 已推送记录（去重）
    existing_queue = await load_existing_queue_keys(session, content_id)
    existing_pushed = await load_existing_pushed_keys(session, content_id)

    count = 0
    for rule in rules:
        for target, bot_chat in targets_map.get(rule.id, []):
            # Watermark 检查：旧内容跳过
            if content.created_at < target.backfill_watermark:
                continue

            # 统一判定
            decision = should_distribute(content, rule, bot_chat)
            if not decision.push:
                continue

            # 去重
            key = (rule.id, bot_chat.id)
            if key in existing_queue or (content_id, decision.target_id) in existing_pushed:
                continue

            # 直接创建 SCHEDULED 队列项（不计算排期，Worker 消费时再算）
            session.add(ContentQueueItem(
                content_id=content_id,
                rule_id=rule.id,
                bot_chat_id=bot_chat.id,
                target_platform=bot_chat.platform_type,
                target_id=decision.target_id,
                status=QueueItemStatus.SCHEDULED,
                priority=rule.priority + content.queue_priority,
                nsfw_routing_result=decision.nsfw_routing_result,
            ))
            count += 1

    if count:
        await session.commit()
    return count
```

#### 1.4.3 Worker 限流移入

```python
# tasks/distribution_worker.py — _claim_items 改动

async def _claim_items(self, session, worker_name) -> list:
    now = utcnow()
    items = await fetch_scheduled_items(session, limit=BATCH_SIZE)

    claimable = []
    for item in items:
        # 限流检查移到这里
        rule = await get_rule(session, item.rule_id)
        if rule.rate_limit and rule.time_window:
            if not self._check_rate_limit(session, item, rule, now):
                continue  # 跳过，下次轮询再检查

        item.status = QueueItemStatus.PROCESSING
        item.locked_at = now
        item.locked_by = worker_name
        claimable.append(item)

    await session.commit()
    return claimable
```

#### 1.4.4 审批触发入队

```python
# services/content_service.py

async def review_card(self, card_id, action, ...):
    ...
    if is_approve:
        # 直接入队（不再有 auto_approve 路径）
        await enqueue_content(content.id, session=self.db)

# tasks/parsing.py — _check_auto_approval 简化

async def _check_auto_approval(self, session, content):
    """解析完成后：检查是否所有匹配规则都不需要审批"""
    rules = await load_enabled_rules(session)
    for rule in rules:
        if not rule.approval_required:
            # 存在免审批规则 → 自动通过
            decision = check_match_conditions(content, rule.match_conditions)
            if decision.push:
                content.review_status = ReviewStatus.AUTO_APPROVED
                content.reviewed_at = utcnow()
                content.review_note = f"Auto-approved (rule: {rule.name})"
                await session.commit()
                await enqueue_content(content.id, session=session)
                return
```

### 1.5 迁移策略

1. **数据库迁移**：
   - 新增 `distribution_targets.backfill_watermark` 列（默认值 = `created_at`）
   - 删除 `content_queue_items.needs_approval`、`content_queue_items.approved_at` 列
   - 删除 `distribution_rules.auto_approve_conditions` 列（先备份）
   - 清理 `status IN ('pending', 'skipped')` 的历史队列项

2. **代码迁移**：
   - 合并 `decision.py` 的三个函数为 `should_distribute`
   - 简化 `scheduler.py` 的 `enqueue_content`
   - 删除 `mark_historical_parse_success_as_pushed_for_rule`
   - 移动 `compute_auto_scheduled_at` 到 `distribution_worker.py`

3. **前端适配**：
   - 规则创建表单：移除 `auto_approve_conditions` 字段
   - 队列面板：移除 PENDING/SKIPPED 状态筛选

---

## 2. 多平台收藏自动导入

### 2.1 实现策略

**核心原则：研究并复刻，而非全量依赖。**

默认不将外部 CLI 工具作为运行时依赖（subprocess 调用），而是研究其收藏读取的 API 调用逻辑，将核心请求链路复刻为 VaultStream 原生的 `FavoritesFetcher`，与现有 adapter 体系风格一致。

例外说明：Twitter 因 TLS 指纹风控，允许短期采用 subprocess 桥接作为过渡方案，后续切换到原生实现。

理由：
- 避免 Docker 镜像中安装额外 CLI 工具 + 管理其登录态
- 可复用现有的 cookie 管理（数据库 settings 表 / 浏览器扫码登录）
- 反风控策略可统一管控（已有 `_rate_limit_delay` 等基础设施）

> **开源致谢**：小红书收藏读取逻辑参考自 [xiaohongshu-cli](https://github.com/jackwener/xiaohongshu-cli)（Apache-2.0），
> Twitter 书签读取逻辑参考自 [twitter-cli](https://github.com/jackwener/twitter-cli)（Apache-2.0），
> 知乎收藏夹读取逻辑参考自 [ZhihuCollectionsPro](https://github.com/ienone/ZhihuCollectionsPro)（MIT）。
> 相关代码文件头部应保留致谢注释。

### 2.2 各平台 API 分析

#### 2.2.1 小红书收藏

**来源**：研究 `xiaohongshu-cli` 的 `client_mixins.py` → `get_user_favorites`

| 项目 | 值 |
|------|-----|
| 端点 | `GET https://edith.xiaohongshu.com/api/sns/web/v2/note/collect/page` |
| 参数 | `user_id` (字符串), `cursor` (空字符串=首页), `num` (30) |
| 认证 | Cookie (`a1`, `web_session`, `webId` 等) |
| 签名 | `x-s`, `x-s-common`, `x-t`, `x-b3-traceid`, `x-xray-traceid`（通过 `xhshow` 库计算） |
| 分页 | cursor-based, 响应中 `{ has_more: bool, cursor: "opaque" }` |
| 响应 | `{ success: true, data: { notes: [...], has_more, cursor } }` |
| 风控码 | HTTP 461/471=验证码, code -100=session过期, 300012=IP封禁 |

**VaultStream 已有基础**：`xhshow` 已在 `requirements.txt` 中，`XiaohongshuAdapter` 已使用该签名。

#### 2.2.2 Twitter/X 书签

**来源**：研究 `twitter-cli` 的 `client.py` → `fetch_bookmarks`, `graphql.py`

| 项目 | 值 |
|------|-----|
| 端点 | `GET https://x.com/i/api/graphql/{queryId}/Bookmarks` |
| queryId | `uzboyXSHSJrR-mGJqep0TQ`（会定期轮换，需 fallback 机制） |
| Variables | `{"count": 40, "includePromotedContent": false, "latestControlAvailable": true, "requestContext": "launch"}` |
| 分页 | `cursor` 参数加入 variables, 从响应 entries 中 `cursorType=="Bottom"` 提取 |
| 认证 | `Authorization: Bearer <固定公共token>`, `Cookie: auth_token=X; ct0=Y`, `X-Csrf-Token: <ct0>` |
| 响应路径 | `data.bookmark_timeline.timeline.instructions[].entries[].content.itemContent.tweet_results.result` |
| TLS 指纹 | 需 `curl_cffi` 模拟 Chrome 指纹（现有 `httpx` 可能不够，需评估是否引入） |

**注意**：Twitter 的反风控依赖 TLS 指纹伪装（`curl_cffi`），比其他平台复杂。

#### 2.2.3 知乎收藏夹

**来源**：研究 [ZhihuCollectionsPro](https://github.com/ienone/ZhihuCollectionsPro) 油猴脚本的 API 调用

原脚本在浏览器环境运行，主要是为了：
1. 自动携带登录 Cookie
2. 绕过 `x-zse-96` 签名（通过 `GM_xmlhttpRequest` 跨域请求 HTML 而非调用受保护的 API）

**但收藏夹列表 API 本身不需要 `x-zse-96` 签名**，只需要有效的 Cookie + `_xsrf` token。
在 VaultStream 中 cookie 已通过扫码登录持久化到数据库，可以直接在非浏览器环境调用。

| 项目 | 值 |
|------|-----|
| 获取用户收藏夹列表 | `GET https://www.zhihu.com/api/v4/people/{user_id}/collections?limit=20&offset=0` |
| 获取收藏夹内容 | `GET https://www.zhihu.com/api/v4/collections/{collection_id}/items?limit=20&offset=0` |
| 认证 | Cookie（需包含 `z_c0`, `_xsrf` 等），Header 需带 `x-xsrftoken` |
| 分页 | offset-based, 响应 `{ paging: { is_end: bool, next: "full_url" } }` |
| 响应 | `{ data: [...], paging: { is_end, next, totals } }` |
| 内容类型 | `data[].content.type` = `"answer"` / `"article"` / `"zvideo"` |

**VaultStream 已有基础**：`ZhihuAdapter` 已有完整的 API headers、cookie 管理、`_xsrf` token 处理。

### 2.3 架构概览

```
┌──────────────────────────────────────────────────────────────┐
│                    FavoritesSyncTask                          │
│                (后台定时任务 / 手动触发 / Agent Tool)           │
├──────────┬──────────┬──────────┬─────────────────────────────┤
│   XHS    │ Twitter  │  Zhihu   │  ... 可扩展 (Bilibili等)    │
│ Fetcher  │ Fetcher  │ Fetcher  │                             │
├──────────┴──────────┴──────────┴─────────────────────────────┤
│         BaseFavoritesFetcher (原生实现，复用现有 adapter 风格)   │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  复用现有 cookie 管理 (settings 表 / 浏览器扫码登录)     │  │
│  │  复用现有 httpx AsyncClient + 签名基础设施              │  │
│  │  内置 Gaussian jitter + 指数退避 + 限流                 │  │
│  └────────────────────────────────────────────────────────┘  │
├──────────────────────────────────────────────────────────────┤
│         ContentService.create_share()  (去重入库)             │
└──────────────────────────────────────────────────────────────┘
```

### 2.4 详细设计

#### 2.4.1 Fetcher 抽象层

```python
# backend/app/adapters/favorites/base.py

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional


@dataclass
class FavoriteItem:
    """各平台收藏项的统一表示"""
    url: str
    title: Optional[str] = None
    platform: Optional[str] = None
    item_id: Optional[str] = None         # 平台原生 ID
    author: Optional[str] = None
    cover_url: Optional[str] = None
    media_urls: list[str] = field(default_factory=list)
    favorited_at: Optional[datetime] = None
    content_type: Optional[str] = None    # "answer"/"article"/"note"/"tweet"


class BaseFavoritesFetcher(ABC):
    """平台收藏拉取器基类 — 原生实现，不依赖外部 CLI"""

    @abstractmethod
    async def fetch_favorites(
        self,
        *,
        max_items: int = 50,
        cursor: Optional[str] = None,
    ) -> tuple[list[FavoriteItem], Optional[str]]:
        """
        拉取收藏列表。

        Returns:
            (items, next_cursor) — cursor 为 None 表示已到底
        """

    @abstractmethod
    async def check_auth(self) -> bool:
        """检查登录状态（cookie 是否有效）"""

    @abstractmethod
    def platform_name(self) -> str:
        """返回平台标识"""
```

#### 2.4.2 知乎收藏夹 Fetcher

```python
# backend/app/adapters/favorites/zhihu_fetcher.py
#
# 知乎收藏夹读取逻辑参考自：
# - ZhihuCollectionsPro (https://github.com/ienone/ZhihuCollectionsPro) MIT License
# - 知乎 Web API 逆向分析
#
# 本实现为原生 Python 复刻，复用 VaultStream 已有的 cookie 管理和 HTTP 基础设施。

import asyncio
import random
from typing import Optional

import httpx
from app.core.logging import logger
from app.adapters.favorites.base import BaseFavoritesFetcher, FavoriteItem
from app.adapters.zhihu import ZhihuAdapter
from app.services.settings_service import get_setting_value


class ZhihuFavoritesFetcher(BaseFavoritesFetcher):
    """知乎收藏夹拉取器"""

    def platform_name(self) -> str:
        return "zhihu"

    async def _get_cookies(self) -> dict:
        """从 settings 加载知乎 cookie"""
        cookie_str = await get_setting_value("zhihu_cookie")
        if not cookie_str:
            return {}
        from app.adapters.base import PlatformAdapter
        return PlatformAdapter.parse_cookie_str(cookie_str)

    async def check_auth(self) -> bool:
        cookies = await self._get_cookies()
        return bool(cookies.get("z_c0"))

    async def _api_get(self, url: str, cookies: dict) -> Optional[dict]:
        """带限流和重试的 GET 请求"""
        headers = {
            **ZhihuAdapter.API_HEADERS,
            "x-xsrftoken": cookies.get("_xsrf", ""),
        }

        async with httpx.AsyncClient(
            headers=headers,
            cookies=cookies,
            follow_redirects=True,
            timeout=15.0,
        ) as client:
            for attempt in range(3):
                try:
                    # Gaussian jitter
                    jitter = max(0, random.gauss(0.5, 0.2))
                    await asyncio.sleep(1.0 + jitter)

                    resp = await client.get(url)
                    if resp.status_code == 200:
                        return resp.json()
                    if resp.status_code in (401, 403):
                        logger.warning(f"[zhihu favorites] auth failed: {resp.status_code}")
                        return None
                    if resp.status_code == 429 or resp.status_code >= 500:
                        wait = (2 ** attempt) + random.uniform(0, 1)
                        logger.warning(f"[zhihu favorites] {resp.status_code}, retrying in {wait:.1f}s")
                        await asyncio.sleep(wait)
                        continue
                except httpx.RequestError as e:
                    logger.warning(f"[zhihu favorites] request error: {e}")
                    if attempt < 2:
                        await asyncio.sleep(2 ** attempt)
        return None

    async def _fetch_user_collections(self, cookies: dict) -> list[dict]:
        """获取用户所有收藏夹列表"""
        # 先获取当前用户 ID
        me_url = "https://www.zhihu.com/api/v4/me"
        me_data = await self._api_get(me_url, cookies)
        if not me_data or "url_token" not in me_data:
            logger.warning("[zhihu favorites] failed to get current user info")
            return []

        user_id = me_data["url_token"]
        collections = []
        offset = 0
        limit = 20

        while True:
            url = (
                f"https://www.zhihu.com/api/v4/people/{user_id}"
                f"/collections?limit={limit}&offset={offset}"
            )
            data = await self._api_get(url, cookies)
            if not data:
                break

            for item in data.get("data", []):
                collections.append({
                    "id": str(item.get("id", "")),
                    "title": item.get("title", ""),
                    "item_count": item.get("item_count", 0),
                })

            paging = data.get("paging", {})
            if paging.get("is_end", True):
                break
            offset += limit

        return collections

    async def fetch_favorites(
        self,
        *,
        max_items: int = 50,
        cursor: Optional[str] = None,
    ) -> tuple[list[FavoriteItem], Optional[str]]:
        cookies = await self._get_cookies()
        if not cookies.get("z_c0"):
            return [], None

        # 获取所有收藏夹
        collections = await self._fetch_user_collections(cookies)
        if not collections:
            return [], None

        # 遍历每个收藏夹，拉取内容
        all_items: list[FavoriteItem] = []
        seen_urls: set[str] = set()

        for collection in collections:
            if len(all_items) >= max_items:
                break

            coll_id = collection["id"]
            offset = 0
            limit = 20

            while len(all_items) < max_items:
                url = (
                    f"https://www.zhihu.com/api/v4/collections/{coll_id}"
                    f"/items?limit={limit}&offset={offset}"
                )
                data = await self._api_get(url, cookies)
                if not data:
                    break

                for entry in data.get("data", []):
                    if len(all_items) >= max_items:
                        break

                    content = entry.get("content", {})
                    content_type = content.get("type", "")
                    item_url = content.get("url", "")

                    # 构建标准 URL
                    if content_type == "answer":
                        question = content.get("question", {})
                        qid = question.get("id", "")
                        aid = content.get("id", "")
                        item_url = f"https://www.zhihu.com/question/{qid}/answer/{aid}"
                    elif content_type == "article":
                        aid = content.get("id", "")
                        item_url = f"https://zhuanlan.zhihu.com/p/{aid}"
                    elif not item_url:
                        continue

                    if item_url in seen_urls:
                        continue
                    seen_urls.add(item_url)

                    title = content.get("title") or content.get("question", {}).get("title", "")
                    author = content.get("author", {})

                    all_items.append(FavoriteItem(
                        url=item_url,
                        title=title,
                        platform="zhihu",
                        item_id=str(content.get("id", "")),
                        author=author.get("name"),
                        cover_url=content.get("title_image") or content.get("image_url"),
                        content_type=content_type,
                    ))

                paging = data.get("paging", {})
                if paging.get("is_end", True):
                    break
                offset += limit

        return all_items, None
```

#### 2.4.3 小红书收藏 Fetcher

```python
# backend/app/adapters/favorites/xiaohongshu_fetcher.py
#
# 收藏读取逻辑参考自 xiaohongshu-cli (https://github.com/jackwener/xiaohongshu-cli)
# 原项目采用 Apache-2.0 License，本文件为基于其 API 调用模式的原生复刻实现。

import asyncio
import random
from typing import Optional

import httpx
from xhshow import CryptoConfig, SessionManager, sign_main_api, build_get_uri
from app.core.logging import logger
from app.adapters.favorites.base import BaseFavoritesFetcher, FavoriteItem
from app.services.settings_service import get_setting_value


# 签名配置（对齐 macOS Chrome 145 指纹）
_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"
)
_EDITH_HOST = "https://edith.xiaohongshu.com"


class XiaohongshuFavoritesFetcher(BaseFavoritesFetcher):
    """小红书收藏拉取器"""

    def platform_name(self) -> str:
        return "xiaohongshu"

    async def _get_cookies(self) -> dict:
        cookie_str = await get_setting_value("xiaohongshu_cookie")
        if not cookie_str:
            return {}
        from app.adapters.base import PlatformAdapter
        return PlatformAdapter.parse_cookie_str(cookie_str)

    async def check_auth(self) -> bool:
        cookies = await self._get_cookies()
        return bool(cookies.get("a1") and cookies.get("web_session"))

    def _build_base_headers(self, cookies: dict) -> dict:
        cookie_str = "; ".join(f"{k}={v}" for k, v in cookies.items())
        return {
            "user-agent": _USER_AGENT,
            "content-type": "application/json;charset=UTF-8",
            "cookie": cookie_str,
            "origin": "https://www.xiaohongshu.com",
            "referer": "https://www.xiaohongshu.com/",
            "sec-ch-ua": '"Not:A-Brand";v="99", "Google Chrome";v="145", "Chromium";v="145"',
            "sec-ch-ua-mobile": "?0",
            "sec-ch-ua-platform": '"macOS"',
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "same-site",
            "accept": "application/json, text/plain, */*",
        }

    async def _get_self_user_id(self, cookies: dict) -> Optional[str]:
        """获取当前登录用户 ID"""
        uri = "/api/sns/web/v2/user/me"
        sign_headers = sign_main_api("GET", uri, cookies)
        full_url = f"{_EDITH_HOST}{uri}"

        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(
                full_url,
                headers={**self._build_base_headers(cookies), **sign_headers},
            )
            if resp.status_code == 200:
                data = resp.json()
                if data.get("success"):
                    return data.get("data", {}).get("user_id")
        return None

    async def fetch_favorites(
        self,
        *,
        max_items: int = 50,
        cursor: Optional[str] = None,
    ) -> tuple[list[FavoriteItem], Optional[str]]:
        cookies = await self._get_cookies()
        if not await self.check_auth():
            return [], None

        user_id = await self._get_self_user_id(cookies)
        if not user_id:
            logger.warning("[xhs favorites] failed to get user_id")
            return [], None

        all_items: list[FavoriteItem] = []
        current_cursor = cursor or ""

        while len(all_items) < max_items:
            uri = "/api/sns/web/v2/note/collect/page"
            params = {"user_id": user_id, "cursor": current_cursor, "num": 30}
            sign_headers = sign_main_api("GET", uri, cookies, params=params)
            full_uri = build_get_uri(uri, params)
            full_url = f"{_EDITH_HOST}{full_uri}"

            # Gaussian jitter
            jitter = max(0, random.gauss(0.3, 0.15))
            if random.random() < 0.05:
                jitter += random.uniform(2.0, 5.0)
            await asyncio.sleep(1.0 + jitter)

            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.get(
                    full_url,
                    headers={**self._build_base_headers(cookies), **sign_headers},
                )

            if resp.status_code != 200:
                logger.warning(f"[xhs favorites] HTTP {resp.status_code}")
                break

            body = resp.json()
            if not body.get("success"):
                code = body.get("code")
                if code == -100:
                    logger.warning("[xhs favorites] session expired")
                elif code == 300012:
                    logger.warning("[xhs favorites] IP blocked")
                break

            data = body.get("data", {})
            notes = data.get("notes", [])

            for note in notes:
                if len(all_items) >= max_items:
                    break
                note_id = note.get("note_id", "")
                all_items.append(FavoriteItem(
                    url=f"https://www.xiaohongshu.com/explore/{note_id}",
                    title=note.get("display_title") or note.get("title"),
                    platform="xiaohongshu",
                    item_id=note_id,
                    author=note.get("user", {}).get("nickname"),
                    cover_url=note.get("cover", {}).get("url_default")
                              or note.get("cover", {}).get("url"),
                ))

            if not data.get("has_more", False):
                current_cursor = None
                break
            current_cursor = data.get("cursor", "")

        return all_items, current_cursor
```

#### 2.4.4 Twitter/X 书签 Fetcher

Twitter 的反风控严重依赖 TLS 指纹伪装（`curl_cffi`）。提供两种实现策略：

**策略 A（推荐先行）**：subprocess 调用已安装的 `twitter-cli`，作为过渡方案。
**策略 B（远期）**：引入 `curl_cffi` 依赖后原生复刻 GraphQL 调用。

```python
# backend/app/adapters/favorites/twitter_fetcher.py
#
# Twitter 书签读取逻辑参考自 twitter-cli (https://github.com/jackwener/twitter-cli)
# 原项目采用 Apache-2.0 License。
#
# 当前采用 subprocess 桥接模式（Twitter 需要 curl_cffi TLS 指纹伪装，
# 原生 httpx 无法绕过），远期可引入 curl_cffi 后切换为原生实现。

import asyncio
import json
from typing import Optional

from app.core.logging import logger
from app.adapters.favorites.base import BaseFavoritesFetcher, FavoriteItem


class TwitterFavoritesFetcher(BaseFavoritesFetcher):
    """Twitter 书签拉取器 (subprocess 桥接模式)"""

    def platform_name(self) -> str:
        return "twitter"

    async def check_auth(self) -> bool:
        """检查 twitter-cli 是否已安装且已登录"""
        try:
            proc = await asyncio.create_subprocess_exec(
                "twitter", "feed", "--max", "1", "--json",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            _, stderr = await asyncio.wait_for(proc.communicate(), timeout=30)
            return proc.returncode == 0
        except (FileNotFoundError, asyncio.TimeoutError):
            return False

    async def fetch_favorites(
        self,
        *,
        max_items: int = 50,
        cursor: Optional[str] = None,
    ) -> tuple[list[FavoriteItem], Optional[str]]:
        try:
            proc = await asyncio.create_subprocess_exec(
                "twitter", "bookmarks", "--max", str(max_items), "--json",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=120)
        except (FileNotFoundError, asyncio.TimeoutError) as e:
            logger.error(f"[twitter favorites] subprocess error: {e}")
            return [], None

        if proc.returncode != 0:
            logger.error(f"[twitter favorites] failed: {stderr.decode()[:500]}")
            return [], None

        try:
            data = json.loads(stdout.decode())
        except json.JSONDecodeError:
            logger.error("[twitter favorites] invalid JSON output")
            return [], None

        tweets = data.get("data", data) if isinstance(data, dict) else data
        if not isinstance(tweets, list):
            tweets = [tweets] if isinstance(tweets, dict) else []

        items = []
        for tweet in tweets:
            if len(items) >= max_items:
                break
            tweet_id = tweet.get("id", "")
            author = tweet.get("author", {})
            screen_name = author.get("screen_name", "")
            items.append(FavoriteItem(
                url=f"https://x.com/{screen_name}/status/{tweet_id}",
                title=(tweet.get("text", "") or "")[:100],
                platform="twitter",
                item_id=str(tweet_id),
                author=author.get("name") or screen_name,
                cover_url=None,
                content_type="tweet",
            ))

        return items, None
```

#### 2.4.5 同步任务编排

```python
# backend/app/tasks/favorites_sync.py

import asyncio
from app.core.database import AsyncSessionLocal
from app.core.logging import logger
from app.services.content_service import ContentService
from app.services.settings_service import get_setting_value
from app.adapters.favorites.base import BaseFavoritesFetcher


class FavoritesSyncTask:
    """定期同步各平台收藏到 VaultStream 主库"""

    def __init__(self):
        self._task: asyncio.Task | None = None
        self._fetchers: dict[str, type[BaseFavoritesFetcher]] = {}
        self._register_fetchers()

    def _register_fetchers(self):
        from app.adapters.favorites.zhihu_fetcher import ZhihuFavoritesFetcher
        from app.adapters.favorites.xiaohongshu_fetcher import XiaohongshuFavoritesFetcher
        from app.adapters.favorites.twitter_fetcher import TwitterFavoritesFetcher
        self._fetchers = {
            "zhihu": ZhihuFavoritesFetcher,
            "xiaohongshu": XiaohongshuFavoritesFetcher,
            "twitter": TwitterFavoritesFetcher,
        }

    def start(self):
        self._task = asyncio.create_task(self._sync_loop())
        logger.info("FavoritesSyncTask started")

    async def stop(self):
        if self._task and not self._task.done():
            self._task.cancel()

    async def _sync_loop(self):
        while True:
            try:
                interval = int(await get_setting_value(
                    "favorites_sync_interval_minutes", 360
                ))
                await self._sync_all_platforms()
            except Exception as e:
                logger.error(f"Favorites sync error: {e}")
            await asyncio.sleep(interval * 60)

    async def _sync_all_platforms(self):
        enabled = await get_setting_value("favorites_sync_platforms", [])
        if not enabled:
            return
        for platform in enabled:
            fetcher_cls = self._fetchers.get(platform)
            if not fetcher_cls:
                continue
            try:
                await self._sync_platform(fetcher_cls())
            except Exception as e:
                logger.error(f"Favorites sync [{platform}] failed: {e}")

    async def _sync_platform(self, fetcher: BaseFavoritesFetcher):
        platform = fetcher.platform_name()

        if not await fetcher.check_auth():
            logger.warning(f"[{platform}] not authenticated, skipping")
            return

        rate_limit = float(await get_setting_value(
            f"favorites_sync_rate_{platform}", 5
        ))
        delay = 60.0 / max(rate_limit, 0.1)
        max_items = int(await get_setting_value("favorites_sync_max_items", 50))

        items, _ = await fetcher.fetch_favorites(max_items=max_items)
        logger.info(f"[{platform}] fetched {len(items)} favorites")

        imported = 0
        async with AsyncSessionLocal() as session:
            svc = ContentService(session)
            for item in items:
                try:
                    await svc.create_share(
                        url=item.url,
                        tags=[],
                        source_name=f"favorites_sync:{platform}",
                    )
                    imported += 1
                except ValueError:
                    continue
                except Exception as e:
                    logger.warning(f"[{platform}] import failed: {item.url}, {e}")
                await asyncio.sleep(delay)

        logger.info(f"[{platform}] imported {imported}/{len(items)} items")

    async def sync_platform_by_name(self, platform: str):
        """手动触发单平台同步 (供 API / Agent 调用)"""
        fetcher_cls = self._fetchers.get(platform)
        if not fetcher_cls:
            raise ValueError(f"Unknown platform: {platform}")
        await self._sync_platform(fetcher_cls())
```

### 2.5 风控与限流

```
第 1 层: 请求级反风控 (各 Fetcher 内置)
├── Gaussian jitter (请求间隔 1s + 随机偏移)
├── 5% 概率长暂停 (2-5s，模拟阅读行为)
├── 指数退避重试 (HTTP 429/5xx, 最多 3 次)
└── 平台签名/指纹对齐 (xhshow 签名 / Chrome UA)

第 2 层: 同步级速率控制
├── favorites_sync_interval_minutes = 360 (默认 6 小时同步一次)
├── favorites_sync_max_items = 50 (单次最多拉取 50 条)
└── 顺序同步各平台 (不并发，避免叠加请求)

第 3 层: 入库级速率控制
├── favorites_sync_rate_{platform} (每分钟入库上限，可分平台配置)
│   ├── zhihu     默认 5/min
│   ├── xiaohongshu 默认 3/min (风控最严)
│   └── twitter   默认 5/min
└── asyncio.sleep(60 / rate) 逐条限流
```

### 2.6 数据模型

```python
# 复用现有 settings 表存储同步配置，无需新表

# settings 键值设计:
#   favorites_sync_platforms          = ["zhihu", "xiaohongshu", "twitter"]
#   favorites_sync_interval_minutes   = 360
#   favorites_sync_rate_zhihu         = 5
#   favorites_sync_rate_xiaohongshu   = 3
#   favorites_sync_rate_twitter       = 5
#   favorites_sync_max_items          = 50

# 通过 content_sources.source 字段标记来源:
#   source = "favorites_sync:zhihu"
#   source = "favorites_sync:xiaohongshu"
#   source = "favorites_sync:twitter"

# 去重完全复用 ContentService.create_share() 的 canonical_url 逻辑
```

### 2.7 开源许可合规

| 参考项目 | License | 复用方式 | 合规措施 |
|----------|---------|---------|---------|
| [xiaohongshu-cli](https://github.com/jackwener/xiaohongshu-cli) | Apache-2.0 | API 调用模式复刻 | 文件头致谢注释 + README 致谢 |
| [twitter-cli](https://github.com/jackwener/twitter-cli) | Apache-2.0 | subprocess 桥接 / API 模式复刻 | 文件头致谢注释 + README 致谢 |
| [ZhihuCollectionsPro](https://github.com/ienone/ZhihuCollectionsPro) | MIT | API 端点分析 | 文件头致谢注释 (自有项目) |

每个 Fetcher 文件头部应包含如下注释：
```python
# 收藏读取逻辑参考自 [项目名] (https://github.com/...)
# 原项目采用 [License] License。
# 本文件为基于其 API 调用模式的原生复刻实现，非原始代码的直接复制。
```

### 2.8 前端配置

在 **设置 → 收藏同步** 中新增面板：

```
┌──────────────────────────────────────────────┐
│  收藏自动同步                                  │
│                                              │
│  [✓] 知乎     状态: 已登录   速率: 5条/分钟    │
│  [✓] 小红书   状态: 已登录   速率: 3条/分钟    │
│  [✓] Twitter  状态: 已安装   速率: 5条/分钟    │
│  [ ] Bilibili 状态: 待实现                    │
│                                              │
│  同步间隔:  [360] 分钟                         │
│  单次上限:  [50] 条                            │
│                                              │
│  上次同步: 2026-03-17 08:00                   │
│  [手动同步]                                    │
└──────────────────────────────────────────────┘
```

---

## 3. 大模型深度集成

### 3.1 RAG 语义检索

#### 3.1.1 架构

```
                  ┌─────────────────────────────────┐
                  │        Hybrid Search Engine       │
                  │                                   │
  用户查询 ──────→│  1. Query Embedding (text-embedding)│
  "上周看过的     │  2. Vector Search (top-K=20)       │
   Rust异步文章"  │  3. FTS5 关键词搜索 (top-K=20)     │
                  │  4. RRF 融合排序                   │
                  │  5. (可选) LLM Rerank              │
                  └────────────┬────────────────────┘
                               ↓
                        返回排序结果
```

#### 3.1.2 Embedding 管线

```python
# backend/app/services/embedding_service.py

class EmbeddingService:
    """内容向量化服务"""

    async def embed_content(self, content: Content) -> list[float]:
        """
        将内容转为 embedding 向量。

        输入拼接策略:
          "[title]\n[tags joined]\n[body[:2000]]"
        """

    async def embed_query(self, query: str) -> list[float]:
        """将用户查询转为 embedding 向量"""

    async def index_content(self, content_id: int):
        """
        生成 embedding 并写入向量存储。

        调用时机: parsing.py _update_content 成功后
        """

    async def search(
        self, query: str, *, top_k: int = 20, filters: dict = None
    ) -> list[SearchResult]:
        """混合搜索: 向量 + FTS5 + RRF 融合"""
```

#### 3.1.3 向量存储选型

| 方案 | 优点 | 缺点 | 推荐 |
|------|------|------|------|
| **sqlite-vec** | 零依赖，适配现有 SQLite 架构 | 生态较新 | ✅ 首选 |
| Chroma | langchain 原生集成 | 额外服务进程 | 备选 |
| pgvector | 生产级成熟 | 需要 PostgreSQL | 远期 |

选择 **sqlite-vec**：与现有 SQLite 架构统一，无额外依赖。

```python
# 向量表 (通过 sqlite-vec 扩展)
# CREATE VIRTUAL TABLE content_embeddings USING vec0(
#     content_id INTEGER PRIMARY KEY,
#     embedding FLOAT[1536]       -- 维度取决于 embedding 模型
# );
```

#### 3.1.4 RRF (Reciprocal Rank Fusion) 融合

```python
def rrf_merge(
    vector_results: list[int],   # content_ids from vector search
    fts_results: list[int],      # content_ids from FTS5
    k: int = 60,
) -> list[tuple[int, float]]:
    """
    RRF 融合: score(d) = Σ 1/(k + rank(d))

    两个检索源各自产出排序列表，RRF 合并后产出最终排序。
    """
    scores = {}
    for rank, cid in enumerate(vector_results):
        scores[cid] = scores.get(cid, 0) + 1.0 / (k + rank)
    for rank, cid in enumerate(fts_results):
        scores[cid] = scores.get(cid, 0) + 1.0 / (k + rank)
    return sorted(scores.items(), key=lambda x: -x[1])
```

#### 3.1.5 API 端点

```
GET /api/v1/search/semantic
  ?q=上周看过的Rust异步文章
  &top_k=10
  &platform=bilibili     (可选过滤)
  &date_from=2026-03-10  (可选过滤)

Response:
{
  "results": [
    {
      "content_id": 42,
      "title": "Tokio 深入解析",
      "score": 0.87,
      "highlight": "...Rust 异步运行时...",
      "match_source": "hybrid"    // "vector" | "fts" | "hybrid"
    }
  ]
}
```

### 3.2 Agent 系统

#### 3.2.1 架构

```
┌─────────────────────────────────────────────────────────┐
│                    VaultStream Agent                      │
│                                                          │
│  ┌──────────────┐    ┌──────────────────────────────┐   │
│  │  LLM Backbone │    │         Tool Registry         │   │
│  │ (ChatOpenAI)  │    │                              │   │
│  │  via LLMFactory   │  search_content              │   │
│  └──────┬───────┘    │  filter_content              │   │
│         │            │  push_to_target              │   │
│         ↓            │  list_groups                  │   │
│  ┌──────────────┐    │  create_rule                  │   │
│  │ Agent Loop    │    │  get_stats                   │   │
│  │ (ReAct /      │←──→│  summarize_content           │   │
│  │  Tool Calling)│    │  import_favorites            │   │
│  └──────┬───────┘    │  manage_tags                  │   │
│         │            └──────────────────────────────┘   │
│         ↓                                               │
│  ┌──────────────┐                                       │
│  │ Conversation  │  ← 多轮对话 + 历史上下文              │
│  │   Memory      │                                      │
│  └──────────────┘                                       │
└─────────────────────────────────────────────────────────┘
```

#### 3.2.2 核心实现

```python
# backend/app/services/agent/agent_service.py

from langchain.agents import AgentExecutor, create_tool_calling_agent
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder

class VaultStreamAgent:
    """VaultStream 自然语言 Agent"""

    SYSTEM_PROMPT = """你是 VaultStream 的 AI 助手。你可以帮用户：
    - 搜索和查找收藏的内容
    - 将内容推送到指定群组/频道
    - 创建和管理分发规则
    - 查看系统统计数据
    - 管理标签和内容

    当用户请求推送时，先确认目标内容和目标群组，再执行推送。
    使用中文回复。"""

    def __init__(self):
        self.tools = []  # 由 _register_tools 填充
        self.agent = None
        self.sessions: dict[str, list] = {}  # session_id → chat_history

    async def initialize(self):
        llm = await LLMFactory.get_text_llm()
        if not llm:
            raise RuntimeError("LLM 未配置")

        self._register_tools()

        prompt = ChatPromptTemplate.from_messages([
            ("system", self.SYSTEM_PROMPT),
            MessagesPlaceholder("chat_history"),
            ("human", "{input}"),
            MessagesPlaceholder("agent_scratchpad"),
        ])

        agent = create_tool_calling_agent(llm, self.tools, prompt)
        self.executor = AgentExecutor(
            agent=agent,
            tools=self.tools,
            verbose=True,
            max_iterations=10,
            handle_parsing_errors=True,
        )

    async def chat(self, session_id: str, message: str) -> str:
        history = self.sessions.setdefault(session_id, [])
        result = await self.executor.ainvoke({
            "input": message,
            "chat_history": history,
        })
        # 追加到历史
        history.append(HumanMessage(content=message))
        history.append(AIMessage(content=result["output"]))
        # 保留最近 20 轮
        if len(history) > 40:
            self.sessions[session_id] = history[-40:]
        return result["output"]
```

#### 3.2.3 API 端点

```
# REST 端点 (简单场景)
POST /api/v1/agent/chat
{
  "session_id": "user-xxx",
  "message": "把我昨天收藏的 Rust 相关内容发到技术分享群"
}

# WebSocket 端点 (流式输出)
WS /api/v1/agent/ws?session_id=user-xxx
→ 支持流式输出 Agent 思考过程和最终结果
```

### 3.3 Tool Using 体系

#### 3.3.1 Tool 定义规范

所有 Agent Tool 统一使用 langchain 的 `@tool` 装饰器，放在 `backend/app/services/agent/tools/` 目录下：

```
backend/app/services/agent/
├── __init__.py
├── agent_service.py       # Agent 核心
├── memory.py              # 对话记忆管理
└── tools/
    ├── __init__.py         # 统一注册
    ├── search.py           # search_content, filter_content
    ├── push.py             # push_to_target, push_batch
    ├── groups.py           # list_groups, get_group_info
    ├── rules.py            # create_rule, list_rules, update_rule
    ├── stats.py            # get_dashboard_stats
    ├── content.py          # summarize_content, manage_tags, get_content
    └── sync.py             # import_favorites, sync_status
```

#### 3.3.2 各 Tool 设计

```python
# --- search.py ---

@tool
async def search_content(
    query: str,
    platform: str = None,
    date_from: str = None,
    date_to: str = None,
    tags: list[str] = None,
    limit: int = 10,
) -> str:
    """
    搜索 VaultStream 收藏库中的内容。支持语义搜索和关键词搜索。

    Args:
        query: 搜索关键词或自然语言描述
        platform: 按平台过滤 (bilibili/twitter/xiaohongshu/zhihu/weibo)
        date_from: 起始日期 (YYYY-MM-DD)
        date_to: 结束日期 (YYYY-MM-DD)
        tags: 按标签过滤
        limit: 返回数量上限
    """

@tool
async def filter_content(
    platform: str = None,
    date_from: str = None,
    date_to: str = None,
    tags: list[str] = None,
    is_nsfw: bool = None,
    review_status: str = None,
    limit: int = 20,
) -> str:
    """
    按条件筛选内容（不涉及语义搜索，纯结构化过滤）。

    当用户说"昨天的""最近一周的""bilibili的"等条件时使用此工具。
    """


# --- push.py ---

@tool
async def push_to_target(
    content_ids: list[int],
    group_name: str = None,
    group_id: str = None,
    platform: str = None,
) -> str:
    """
    将指定内容推送到目标群组/频道。

    必须指定 group_name 或 group_id 之一。
    推送前会自动去重（已推送过的内容跳过）。

    Args:
        content_ids: 要推送的内容 ID 列表
        group_name: 群组名称（模糊匹配）
        group_id: 群组 chat_id（精确匹配）
        platform: 推送平台 (telegram/qq)
    """


# --- groups.py ---

@tool
async def list_groups(platform: str = None) -> str:
    """
    列出所有可用的推送目标群组/频道。

    Args:
        platform: 按平台过滤 (telegram/qq)，不传则返回全部
    """


# --- rules.py ---

@tool
async def create_rule(
    name: str,
    platform: str = None,
    tags: list[str] = None,
    target_group: str = None,
    auto_push: bool = True,
) -> str:
    """
    创建一条新的分发规则。

    示例: "以后 Rust 相关的内容自动发到技术群"
      → create_rule(name="Rust自动推送", tags=["Rust"], target_group="技术群", auto_push=True)
    """


# --- stats.py ---

@tool
async def get_dashboard_stats(period: str = "7d") -> str:
    """
    获取系统统计数据。

    Args:
        period: 统计周期 (1d/7d/30d)
    """


# --- content.py ---

@tool
async def summarize_content(content_id: int) -> str:
    """获取或生成指定内容的摘要。"""

@tool
async def manage_tags(
    content_id: int,
    add_tags: list[str] = None,
    remove_tags: list[str] = None,
) -> str:
    """为内容添加或移除标签。"""


# --- sync.py ---

@tool
async def import_favorites(platform: str) -> str:
    """
    手动触发指定平台的收藏同步。

    Args:
        platform: 平台名称 (xiaohongshu/twitter/zhihu)
    """
```

### 3.4 自然语言推送

这是将上述 Agent + Tool 组合后最核心的用户场景：

```
用户: "把我昨天收藏的内容中的 Rust 相关发给技术分享群"

Agent 执行链:
  1. filter_content(date_from="2026-03-16", date_to="2026-03-16")
     → 返回 15 条内容
  2. search_content(query="Rust", date_from="2026-03-16")
     → 返回 3 条内容 [id=42, id=58, id=71]
  3. list_groups()
     → 找到 "技术分享群" (chat_id="-100123456")
  4. push_to_target(content_ids=[42,58,71], group_name="技术分享群")
     → 推送成功 3 条

Agent 回复:
  "已将 3 条 Rust 相关内容推送到「技术分享群」：
   1. 《Tokio 深入解析》
   2. 《Rust 异步运行时对比》
   3. 《async-std vs tokio 性能测试》"
```

更多场景示例：

| 用户指令 | Agent Tool 调用链 |
|---------|-----------------|
| "最近有什么关于 LLM 的好文章" | `search_content("LLM", date_from="7d_ago")` |
| "把 id 42 的文章发到所有群" | `list_groups()` → `push_to_target([42], ...)` × N |
| "以后小红书的穿搭内容自动发到生活群" | `create_rule(platform="xiaohongshu", tags=["穿搭"], target="生活群")` |
| "同步一下推特收藏" | `import_favorites("twitter")` |
| "这周推了多少条" | `get_dashboard_stats("7d")` |
| "帮我总结一下 id 58 的内容" | `summarize_content(58)` |

### 3.5 数据模型

```python
# backend/app/models/agent.py (新增)

class AgentConversation(Base):
    """Agent 对话记录"""
    __tablename__ = "agent_conversations"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    session_id: Mapped[str] = mapped_column(String(100), index=True)
    role: Mapped[str] = mapped_column(String(20))  # "user" | "assistant" | "tool"
    content: Mapped[str] = mapped_column(Text)
    tool_calls: Mapped[Any | None] = mapped_column(JSON, default=None)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


# 向量索引表 (sqlite-vec 虚拟表，通过 migration 创建)
# CREATE VIRTUAL TABLE content_embeddings USING vec0(
#     content_id INTEGER PRIMARY KEY,
#     embedding FLOAT[1536]
# );
```

---

## 4. 路线图（Phase 划分）

按技术依赖关系和就业价值排序，不含时间规划。

### Phase 1: 推送系统简化

**目标**：减少维护负担，为后续功能提供干净的分发基础。

```
1.1  合并判定函数 → should_distribute()
1.2  删除 auto_approve_conditions，简化审批路径
1.3  删除 PENDING/SKIPPED 队列项概念
1.4  移动限流排期到 Worker 侧
1.5  新增 backfill_watermark 替代历史回填
1.6  数据库迁移脚本
1.7  前端适配（规则表单、队列面板）
1.8  回归测试 (已有 pytest 用例)
```

依赖关系：`1.1 → 1.2 → 1.3 → 1.4 → 1.5 → 1.6 → 1.7 → 1.8`

### Phase 2: RAG 语义检索

**目标**：实现向量化 + 混合搜索，为 Agent 提供检索基础。

```
2.1  引入 sqlite-vec 依赖，创建向量表
2.2  实现 EmbeddingService (embed_content, embed_query)
2.3  解析成功后异步生成 embedding (接入 parsing.py)
2.4  实现 hybrid_search (向量 + FTS5 + RRF)
2.5  暴露 /api/v1/search/semantic 端点
2.6  前端搜索页接入语义搜索
2.7  历史内容批量向量化脚本
```

依赖关系：`2.1 → 2.2 → 2.3 → 2.4 → 2.5 → 2.6`，`2.7` 可并行

### Phase 3: Agent 系统 + Tool Calling

**目标**：实现自然语言交互式操作。

```
3.1  定义 Tool 抽象 + 注册机制
3.2  实现基础 Tool 集 (search, filter, list_groups, push)
3.3  实现 VaultStreamAgent (基于 langchain AgentExecutor)
3.4  实现对话记忆 (AgentConversation 持久化)
3.5  暴露 /api/v1/agent/chat REST 端点
3.6  实现 WebSocket 流式端点
3.7  实现高级 Tool (create_rule, manage_tags, stats)
3.8  前端 Agent 聊天面板
3.9  接入 Telegram Bot (向 Bot 发自然语言指令)
```

依赖关系：`Phase 2 完成` → `3.1 → 3.2 → 3.3 → 3.4 → 3.5`，`3.6-3.9` 可并行

### Phase 4: 多平台收藏同步

**目标**：研究外部 CLI 项目的 API 调用模式，原生复刻收藏读取逻辑。

```
4.1  定义 BaseFavoritesFetcher 抽象层
4.2  实现 ZhihuFavoritesFetcher (原生, 复用现有 ZhihuAdapter cookie)
4.3  实现 XiaohongshuFavoritesFetcher (原生, 复用 xhshow 签名)
4.4  实现 TwitterFavoritesFetcher (subprocess 桥接, 远期原生化)
4.5  实现 FavoritesSyncTask (定时/手动)
4.6  限流配置 (settings 表)
4.7  前端设置面板
4.8  接入 Agent Tool (import_favorites)
4.9  开源许可合规 (文件头致谢注释 + README)
4.10 扩展: BilibiliFavoritesFetcher（暂缓，不纳入当前实现范围）
```

依赖关系：`4.1 → 4.2/4.3/4.4 → 4.5 → 4.6 → 4.7`，`4.8` 依赖 Phase 3，`4.10` 可随时扩展

### Phase 依赖图

```
Phase 1 (推送简化)
    │
    ├──→ Phase 2 (RAG)
    │        │
    │        └──→ Phase 3 (Agent)
    │                 │
    │                 └──→ Phase 4.8 (Agent Tool)
    │
    └──→ Phase 4.1-4.7 (收藏同步，可与 Phase 2 并行)
```

### 覆盖核对清单（执行基线）

为避免遗漏，当前执行范围按以下口径核对：

| 范围 | 必须覆盖 | 本轮口径 |
|------|---------|---------|
| Phase 1 | 1.1 - 1.8 全部 | 已进入收尾（含 DB/枚举去旧、迁移脚本、前后端适配） |
| Phase 2 | 2.1 - 2.7 全部 | 必须纳入主线（RAG 不能缺失） |
| Phase 3 | 3.1 - 3.9 全部 | 与 Phase 2 串行主干 + 并行工具扩展 |
| Phase 4 | 4.1 - 4.9 | 当前纳入；4.10(Bilibili) 暂缓 |

并行实施建议：

- Worker A：Phase 2（RAG 基础设施）
- Worker B：Phase 3（Agent 核心与 Tool）
- Worker C：Phase 4.1-4.7（收藏同步）
- Worker D：Phase 1 收尾 + 集成验收 + 上云迁移

---

## 5. 简历包装建议

```
VaultStream — 跨平台知识管理与智能分发系统
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

• 设计并实现 RAG 混合检索引擎，融合向量语义搜索与 FTS5 关键词搜索，
  采用 RRF 排序融合算法，支持自然语言的收藏库查询

• 基于 LangChain Agent + Tool Calling 构建任务型 AI Agent，提供
  8 类工具（搜索/推送/规则管理/统计等），实现自然语言驱动的内容分发

• 多平台内容采集引擎，支持 Bilibili/Twitter/小红书/知乎/微博等 6+ 平台
  的自动解析与收藏同步，集成反风控策略（Gaussian jitter、指纹对齐、指数退避）

• 基于规则引擎的内容分发系统，支持多目标推送、限流排期、NSFW 路由、
  失败指数退避重试，对接 Telegram/QQ 双平台

• 采用 FastAPI + SQLAlchemy Async + SQLite(WAL) 轻量架构，
  Flutter 跨平台客户端（Web/Desktop/Mobile），SSE 实时事件推送

技术栈: Python · FastAPI · SQLAlchemy · SQLite · LangChain · RAG ·
       Flutter · Docker · Playwright · Telegram Bot API · OneBot 11
```

---

*本文档由代码分析自动生成，基于截至 2026-03-17 的项目代码现状。*
