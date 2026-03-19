"""
队列分发 Worker - 轮询 ContentQueueItem 并推送内容。

基于队列的分发模型，支持多 Worker 并发、乐观锁、指数退避重试。
"""
import asyncio
from datetime import datetime, timedelta
from typing import Optional, List

from sqlalchemy import select, and_, func, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.models import (
    ContentQueueItem,
    QueueItemStatus,
    Content,
    ContentStatus,
    DistributionRule,
    BotChat,
    PushedRecord,
    ReviewStatus,
)
from app.push.factory import get_push_service
from app.tasks.distributor import ContentDistributor
from app.core.events import event_bus

# ── 常量 ──────────────────────────────────────────────
POLL_INTERVAL = 5        # 轮询间隔（秒）
BATCH_SIZE = 10          # 每次轮询最多领取的队列项
LOCK_TIMEOUT = 600       # 锁超时（秒），10 分钟内未完成视为过期


async def compute_auto_scheduled_at(
    *,
    session: AsyncSession,
    rule: DistributionRule,
    bot_chat_id: int,
    target_id: str,
):
    """根据规则限流配置计算自动排期时间（消费侧）。"""
    now = utcnow()

    if not rule.rate_limit or not rule.time_window or rule.rate_limit <= 0 or rule.time_window <= 0:
        return now

    min_interval_seconds = max(1, int(rule.time_window) // int(rule.rate_limit))

    latest_queue_result = await session.execute(
        select(func.max(ContentQueueItem.scheduled_at)).where(
            and_(
                ContentQueueItem.rule_id == rule.id,
                ContentQueueItem.bot_chat_id == bot_chat_id,
                ContentQueueItem.status.in_(
                    [
                        QueueItemStatus.SCHEDULED,
                        QueueItemStatus.PROCESSING,
                        QueueItemStatus.FAILED,
                    ]
                ),
            )
        )
    )
    latest_queue_time = latest_queue_result.scalar_one_or_none()

    latest_pushed_result = await session.execute(
        select(func.max(PushedRecord.pushed_at)).where(
            and_(
                PushedRecord.target_id == target_id,
                PushedRecord.push_status == "success",
            )
        )
    )
    latest_pushed_time = latest_pushed_result.scalar_one_or_none()

    scheduled_at = now
    anchor = latest_queue_time or latest_pushed_time
    if anchor and anchor + timedelta(seconds=min_interval_seconds) > scheduled_at:
        scheduled_at = anchor + timedelta(seconds=min_interval_seconds)

    window_start = now - timedelta(seconds=int(rule.time_window))
    recent_result = await session.execute(
        select(PushedRecord.pushed_at)
        .where(
            and_(
                PushedRecord.target_id == target_id,
                PushedRecord.push_status == "success",
                PushedRecord.pushed_at >= window_start,
            )
        )
        .order_by(PushedRecord.pushed_at.asc())
    )
    recent_pushes = [p for p in recent_result.scalars().all() if p is not None]
    if len(recent_pushes) >= int(rule.rate_limit):
        throttle_until = recent_pushes[0] + timedelta(seconds=int(rule.time_window))
        if throttle_until > scheduled_at:
            scheduled_at = throttle_until

    return scheduled_at


class DistributionQueueWorker:
    """基于队列的分发 Worker"""

    def __init__(self, worker_count: int = 3):
        self.worker_count = worker_count
        self.running = False
        self._tasks: list[asyncio.Task] = []
        self._distributor = ContentDistributor()

    def start(self):
        """启动所有 worker"""
        if self.running:
            return
        self.running = True
        for i in range(self.worker_count):
            task = asyncio.create_task(
                self._worker_loop(f"queue-worker-{i}"),
                name=f"queue-worker-{i}",
            )
            self._tasks.append(task)
        logger.info("分发队列Worker启动 worker_count={}", self.worker_count)

    async def stop(self):
        """停止所有 worker"""
        self.running = False
        for task in self._tasks:
            task.cancel()
        for task in self._tasks:
            try:
                await task
            except asyncio.CancelledError:
                pass
        self._tasks.clear()
        logger.info("分发队列Worker停止")

    async def process_item_now(self, item_id: int, worker_name: str = "api-manual"):
        """立即处理指定队列项（绕过轮询，复用同一推送逻辑）。"""
        async with AsyncSessionLocal() as session:
            result = await session.execute(
                select(ContentQueueItem).where(ContentQueueItem.id == item_id)
            )
            item = result.scalar_one_or_none()
            if not item:
                raise ValueError("Queue item not found")

            if item.status in (
                QueueItemStatus.SUCCESS,
            ):
                raise ValueError(f"Queue item status not pushable: {item.status.value}")

            now = utcnow()
            item.status = QueueItemStatus.PROCESSING
            item.locked_at = now
            item.locked_by = worker_name
            item.scheduled_at = now
            if item.started_at is None:
                item.started_at = now
            await session.commit()

            await self._process_item(session, item, worker_name)

    # ── 主循环 ────────────────────────────────────────

    async def _worker_loop(self, worker_name: str):
        """单个 worker 的主循环。"""
        logger.info("Worker {} 开始运行", worker_name)
        while self.running:
            try:
                async with AsyncSessionLocal() as session:
                    items = await self._claim_items(session, worker_name)
                    if not items:
                        await asyncio.sleep(POLL_INTERVAL)
                        continue

                    for item in items:
                        try:
                            await self._process_item(session, item, worker_name)
                        except Exception as e:
                            logger.error(
                                f"Worker {worker_name} 处理失败 item_id={item.id} error={e}",
                                exc_info=True,
                            )
                            await session.rollback()
            except asyncio.CancelledError:
                raise
            except Exception as e:
                logger.error(
                    f"Worker {worker_name} 循环异常: {e}",
                    exc_info=True,
                )
                await asyncio.sleep(10)

    # ── 领取队列项 ────────────────────────────────────

    async def _claim_items(
        self, session: AsyncSession, worker_name: str
    ) -> List[ContentQueueItem]:
        """
        领取待处理的队列项（乐观锁）。

        筛选条件：
        - SCHEDULED 状态，或 FAILED 且已到重试时间
        - 已到排期时间（scheduled_at <= now）
        - 未被锁定，或锁已过期
        """
        now = utcnow()
        lock_expire = now - timedelta(seconds=LOCK_TIMEOUT)

        base_conditions = [
            or_(
                ContentQueueItem.scheduled_at.is_(None),
                ContentQueueItem.scheduled_at <= now,
            ),
            or_(
                ContentQueueItem.locked_at.is_(None),
                ContentQueueItem.locked_at < lock_expire,
            ),
            BotChat.enabled == True,
            BotChat.is_accessible == True,
        ]

        order_by_cols = (
            ContentQueueItem.priority.desc(),
            ContentQueueItem.scheduled_at.asc(),
            ContentQueueItem.id.asc(),
        )

        scheduled_stmt = (
            select(ContentQueueItem)
            .join(BotChat, BotChat.id == ContentQueueItem.bot_chat_id)
            .where(
                and_(
                    ContentQueueItem.status == QueueItemStatus.SCHEDULED,
                    *base_conditions,
                )
            )
            .order_by(*order_by_cols)
            .limit(BATCH_SIZE)
        )
        failed_stmt = (
            select(ContentQueueItem)
            .join(BotChat, BotChat.id == ContentQueueItem.bot_chat_id)
            .where(
                and_(
                    ContentQueueItem.status == QueueItemStatus.FAILED,
                    ContentQueueItem.next_attempt_at <= now,
                    *base_conditions,
                )
            )
            .order_by(*order_by_cols)
            .limit(BATCH_SIZE)
        )

        scheduled_rows = await session.execute(scheduled_stmt)
        failed_rows = await session.execute(failed_stmt)

        merged: dict[int, ContentQueueItem] = {}
        for item in scheduled_rows.scalars().all():
            merged[item.id] = item
        for item in failed_rows.scalars().all():
            merged[item.id] = item

        items = sorted(
            merged.values(),
            key=self._claim_sort_key,
        )[:BATCH_SIZE]

        if not items:
            return []

        rule_ids = sorted({item.rule_id for item in items})
        rules_result = await session.execute(
            select(DistributionRule).where(DistributionRule.id.in_(rule_ids))
        )
        rules_map = {rule.id: rule for rule in rules_result.scalars().all()}

        deferred = 0
        claimable: List[ContentQueueItem] = []
        for item in items:
            rule = rules_map.get(item.rule_id)
            if (
                rule is not None
                and rule.rate_limit
                and rule.time_window
                and int(rule.rate_limit) > 0
                and int(rule.time_window) > 0
            ):
                next_allowed = await compute_auto_scheduled_at(
                    session=session,
                    rule=rule,
                    bot_chat_id=item.bot_chat_id,
                    target_id=item.target_id,
                )
                if next_allowed > now:
                    item.scheduled_at = next_allowed
                    deferred += 1
                    continue

            item.status = QueueItemStatus.PROCESSING
            item.locked_at = now
            item.locked_by = worker_name
            if item.started_at is None:
                item.started_at = now
            claimable.append(item)

        await session.commit()

        if deferred:
            logger.debug(
                f"Worker {worker_name} deferred {deferred} item(s) by rate-limit"
            )
        logger.debug(
            f"Worker {worker_name} 领取 {len(claimable)} 项 ids={[i.id for i in claimable]}"
        )
        return claimable

    @staticmethod
    def _claim_sort_key(item: ContentQueueItem):
        # Keep NULL scheduled_at first to match SQL ASC semantics.
        scheduled_at = item.scheduled_at
        return (
            -(item.priority or 0),
            scheduled_at is not None,
            scheduled_at or datetime.min,
            item.id,
        )

    # ── 处理单个队列项 ────────────────────────────────

    async def _process_item(
        self,
        session: AsyncSession,
        item: ContentQueueItem,
        worker_name: str,
    ):
        """处理单个队列项：校验 → 去重 → 构建 → 推送 → 记录。"""
        # 1. 加载关联数据
        content_result = await session.execute(
            select(Content).where(Content.id == item.content_id)
        )
        content = content_result.scalar_one_or_none()

        rule_result = await session.execute(
            select(DistributionRule).where(DistributionRule.id == item.rule_id)
        )
        rule = rule_result.scalar_one_or_none()

        bot_chat_result = await session.execute(
            select(BotChat).where(BotChat.id == item.bot_chat_id)
        )
        bot_chat = bot_chat_result.scalar_one_or_none()

        # 1.1 目标可用性兜底（防止领取后被关闭/失联）
        if not bot_chat or not bool(bot_chat.enabled) or not bool(bot_chat.is_accessible):
            item.status = QueueItemStatus.SCHEDULED
            item.last_error = "Target disabled or inaccessible"
            item.last_error_type = "target_unavailable"
            item.locked_at = None
            item.locked_by = None
            await session.commit()
            logger.info(
                "队列项暂缓(目标不可用) item_id=%s bot_chat_id=%s",
                item.id,
                item.bot_chat_id,
            )
            return

        # 2. 资格检查
        if not content or content.review_status not in (
            ReviewStatus.APPROVED,
            ReviewStatus.AUTO_APPROVED,
        ) or content.status != ContentStatus.PARSE_SUCCESS:
            item.status = QueueItemStatus.FAILED
            item.last_error = "Content not eligible"
            item.last_error_type = "content_not_eligible"
            item.next_attempt_at = None
            item.locked_at = None
            item.locked_by = None
            await session.commit()
            logger.info(
                f"队列项跳过(不符合) item_id={item.id} content_id={item.content_id}"
            )
            return

        # 3. 去重检查
        dedupe_result = await session.execute(
            select(PushedRecord).where(
                and_(
                    PushedRecord.content_id == item.content_id,
                    PushedRecord.target_id == item.target_id,
                )
            ).limit(1)
        )
        if dedupe_result.scalar_one_or_none():
            item.status = QueueItemStatus.FAILED
            item.last_error = "Already pushed (dedupe)"
            item.last_error_type = "already_pushed_dedupe"
            item.next_attempt_at = None
            item.locked_at = None
            item.locked_by = None
            await session.commit()
            logger.info(
                f"队列项跳过(重复) item_id={item.id} content_id={item.content_id} target_id={item.target_id}"
            )
            return

        # 4. 确定实际推送目标
        actual_target_id = item.target_id
        if item.nsfw_routing_result and isinstance(item.nsfw_routing_result, dict):
            routed_id = item.nsfw_routing_result.get("target_id")
            if routed_id:
                actual_target_id = routed_id

        # 5. 构建推送 payload
        content_dict = await self._distributor._build_content_payload(content, rule)

        # 6. 推送
        try:
            push_service = get_push_service(item.target_platform)
            message_id = await push_service.push(content_dict, actual_target_id)
        except Exception as e:
            await self._handle_failure(session, item, e)
            return

        if not message_id:
            await self._handle_failure(
                session, item, RuntimeError("Push returned no message_id")
            )
            return

        # 7. 成功处理
        now = utcnow()
        item.status = QueueItemStatus.SUCCESS
        item.message_id = str(message_id)
        item.completed_at = now
        item.last_error = None
        item.last_error_type = None
        item.last_error_at = None
        item.next_attempt_at = None
        item.locked_at = None
        item.locked_by = None

        # 写入推送记录
        pushed = PushedRecord(
            content_id=item.content_id,
            target_platform=item.target_platform,
            target_id=actual_target_id,
            message_id=str(message_id),
            push_status="success",
        )
        session.add(pushed)

        # 更新 BotChat 统计
        if bot_chat:
            bot_chat.total_pushed = (bot_chat.total_pushed or 0) + 1
            bot_chat.last_pushed_at = now

        await session.commit()

        await event_bus.publish("content_pushed", {
            "content_id": item.content_id,
            "rule_id": item.rule_id,
            "bot_chat_id": item.bot_chat_id,
            "target_id": actual_target_id,
            "message_id": str(message_id),
            "queue_item_id": item.id,
            "timestamp": now.isoformat(),
        })
        await event_bus.publish("distribution_push_success", {
            "content_id": item.content_id,
            "queue_item_id": item.id,
            "target_id": actual_target_id,
            "attempt_count": item.attempt_count,
            "timestamp": now.isoformat(),
        })
        await event_bus.publish("queue_updated", {
            "action": "item_success",
            "queue_item_id": item.id,
            "content_id": item.content_id,
            "status": item.status.value,
            "timestamp": now.isoformat(),
        })

        logger.info(
            f"推送成功 item_id={item.id} content_id={item.content_id} target={actual_target_id} message_id={message_id}"
        )

    # ── 失败处理 ──────────────────────────────────────

    async def _handle_failure(
        self,
        session: AsyncSession,
        item: ContentQueueItem,
        error: Exception,
    ):
        """处理推送失败：更新重试计数、计算退避延迟。"""
        now = utcnow()
        item.attempt_count = (item.attempt_count or 0) + 1
        item.last_error = str(error)
        item.last_error_type = type(error).__name__
        item.last_error_at = now
        item.locked_at = None
        item.locked_by = None

        if item.attempt_count >= (item.max_attempts or 3):
            item.status = QueueItemStatus.FAILED
            logger.error(
                f"推送最终失败(已达最大重试) item_id={item.id} "
                f"content_id={item.content_id} attempts={item.attempt_count} "
                f"error={error}"
            )
        else:
            item.status = QueueItemStatus.FAILED
            delay = min(60 * (2 ** item.attempt_count), 3600)
            item.next_attempt_at = now + timedelta(seconds=delay)
            logger.warning(
                f"推送失败将重试 item_id={item.id} "
                f"content_id={item.content_id} attempt={item.attempt_count} "
                f"next_attempt_at={item.next_attempt_at} error={error}"
            )

        await session.commit()

        await event_bus.publish("distribution_push_failed", {
            "content_id": item.content_id,
            "queue_item_id": item.id,
            "status": item.status.value,
            "attempt_count": item.attempt_count,
            "max_attempts": item.max_attempts,
            "next_attempt_at": item.next_attempt_at.isoformat() if item.next_attempt_at else None,
            "error": str(error),
            "timestamp": now.isoformat(),
        })
        await event_bus.publish("queue_updated", {
            "action": "item_failed",
            "queue_item_id": item.id,
            "content_id": item.content_id,
            "status": item.status.value,
            "timestamp": now.isoformat(),
        })


# ── 全局单例 ──────────────────────────────────────────

_queue_worker: Optional[DistributionQueueWorker] = None


def get_queue_worker(worker_count: int = 3) -> DistributionQueueWorker:
    global _queue_worker
    if _queue_worker is None:
        _queue_worker = DistributionQueueWorker(worker_count)
    return _queue_worker
