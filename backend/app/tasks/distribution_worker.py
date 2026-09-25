"""
队列分发 Worker - 轮询 ContentQueueItem 并推送内容。

基于队列的分发模型，支持多 Worker 并发、乐观锁、指数退避重试。
"""
import asyncio
from datetime import datetime, timedelta
from typing import Optional, List
from uuid import uuid4

from sqlalchemy import select, and_, func, or_, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload, aliased

from app.core.database import AsyncSessionLocal
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.models import (
    ContentQueueItem,
    QueueItemStatus,
    Content,
    ContentStatus,
    DistributionRule,
    DistributionTarget,
    BotChat,
    MediaAsset,
    PushedRecord,
    ReviewStatus,
)
from app.push.factory import get_push_service
from app.services.qq_policy import QQRateLimited
from app.services.background_task_state import (
    record_task_run_error,
    record_task_run_started,
    record_task_run_success,
)
from app.services.automation_policy import AutomationPolicyService
from app.services.distribution.decision import should_distribute, DECISION_WILL_PUSH
from app.services.distribution.delivery_state import (
    DELIVERY_PREPARING, DELIVERY_SENDING, DELIVERY_UNKNOWN, LOCK_TIMEOUT,
    UNKNOWN_MESSAGE, delivery_is_resolved, owns_delivery,
    record_delivery_unknown, recover_expired_deliveries,
)
from app.tasks.distributor import ContentDistributor
from app.core.events import event_bus

# ── 常量 ──────────────────────────────────────────────
POLL_INTERVAL = 5        # 轮询间隔（秒）
BATCH_SIZE = 1           # 每个 worker 只领取马上执行的项，不让租约在本地排队过期


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
            await recover_expired_deliveries(session)
            result = await session.execute(
                select(ContentQueueItem).where(ContentQueueItem.id == item_id)
            )
            item = result.scalar_one_or_none()
            if not item:
                raise ValueError("Queue item not found")

            now = utcnow()
            claimed = await session.execute(update(ContentQueueItem).where(
                ContentQueueItem.id == item.id,
                ContentQueueItem.status.in_([QueueItemStatus.SCHEDULED, QueueItemStatus.FAILED]),
                delivery_is_resolved(),
                self._no_delivery_in_flight(item),
            ).values(status=QueueItemStatus.PROCESSING, locked_at=now, locked_by=uuid4().hex,
                last_error_type=DELIVERY_PREPARING, last_error=None,
                attempt_count=ContentQueueItem.attempt_count + 1, next_attempt_at=None,
                scheduled_at=now, started_at=func.coalesce(ContentQueueItem.started_at, now))
                .execution_options(synchronize_session=False))
            if claimed.rowcount != 1:
                raise ValueError("Queue item or the same content target is already processing/completed")
            # Snapshot our own token before commit; never refresh into a later claim.
            await session.refresh(item)
            await session.commit()
            await self._process_item(session, item, worker_name, manual=True)

    @staticmethod
    def _no_delivery_in_flight(item):
        peer = aliased(ContentQueueItem)
        return ~select(peer.id).where(
            peer.id != item.id, peer.content_id == item.content_id,
            peer.target_platform == item.target_platform, peer.target_id == item.target_id,
            or_(peer.status == QueueItemStatus.PROCESSING,
                peer.last_error_type == DELIVERY_UNKNOWN),
        ).exists()

    # ── 主循环 ────────────────────────────────────────

    async def _worker_loop(self, worker_name: str):
        """单个 worker 的主循环。"""
        logger.info("Worker {} 开始运行", worker_name)
        while self.running:
            try:
                result = await self._poll_once(worker_name)
                if not result.get("claimed_count"):
                    await asyncio.sleep(POLL_INTERVAL)
            except asyncio.CancelledError:
                raise
            except Exception as e:
                logger.error(
                    f"Worker {worker_name} 循环异常: {e}",
                    exc_info=True,
                )
                await record_task_run_error("distribution_worker", None, e, worker=worker_name)
                await asyncio.sleep(10)

    async def _poll_once(self, worker_name: str) -> dict:
        """领取并处理一批到期分发队列项。空轮询不创建运行记录。"""
        # Classifying abandoned sends is safe even while automatic delivery is paused.
        async with AsyncSessionLocal() as recovery_session:
            if await recover_expired_deliveries(recovery_session):
                await event_bus.publish("queue_updated", {"action": "delivery_recovered"})
                await event_bus.publish("notification_updated", {"source_type": "distribution_delivery"})
        policy = await AutomationPolicyService().distribution_worker_poll()
        if not policy.allowed:
            logger.bind(worker=worker_name, policy=policy.as_dict()).info(
                "Distribution worker poll skipped by automation policy"
            )
            return {
                "trigger": "auto",
                "worker": worker_name,
                "claimed_count": 0,
                "policy_blocked": True,
                "policy": policy.as_dict(),
            }

        async with AsyncSessionLocal() as session:
            items = await self._claim_items(session, worker_name)
            if not items:
                return {"worker": worker_name, "claimed_count": 0}

            queue_item_ids = [item.id for item in items]
            run = await record_task_run_started(
                "distribution_worker_poll",
                trigger="auto",
                worker=worker_name,
                claimed_count=len(items),
                queue_item_ids=queue_item_ids,
            )
            run_id = run["run_id"]

            status_counts: dict[str, int] = {}
            processed_count = 0
            error_count = 0
            first_error: Exception | None = None

            for item in items:
                item_id = item.id
                try:
                    await self._process_item(session, item, worker_name)
                    processed_count += 1
                    # A fenced-out attempt rolls back and expires its ORM snapshot.
                    await session.refresh(item)
                    status = item.status.value if item.status else "unknown"
                    status_counts[status] = status_counts.get(status, 0) + 1
                except Exception as e:
                    error_count += 1
                    if first_error is None:
                        first_error = e
                    logger.error(
                        f"Worker {worker_name} 处理失败 item_id={item_id} error={e}",
                        exc_info=True,
                    )
                    await session.rollback()

            result = {
                "trigger": "auto",
                "worker": worker_name,
                "claimed_count": len(items),
                "processed_count": processed_count,
                "error_count": error_count,
                "queue_item_ids": queue_item_ids,
                "status_counts": status_counts,
            }

            if first_error is not None:
                await record_task_run_error(
                    "distribution_worker_poll",
                    run_id,
                    first_error,
                    **result,
                )
            else:
                await record_task_run_success(
                    "distribution_worker_poll",
                    run_id,
                    **result,
                )

            return result

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
        - 规则和对应目标关联仍启用
        """
        await recover_expired_deliveries(session)
        now = utcnow()
        lock_expire = now - timedelta(seconds=LOCK_TIMEOUT)

        enabled_rule_target = select(DistributionTarget.id).join(
            DistributionRule, DistributionRule.id == DistributionTarget.rule_id,
        ).where(
            DistributionTarget.rule_id == ContentQueueItem.rule_id,
            DistributionTarget.bot_chat_id == ContentQueueItem.bot_chat_id,
            DistributionTarget.enabled.is_(True),
            DistributionRule.enabled.is_(True),
        ).exists()

        base_conditions = [
            enabled_rule_target,
            delivery_is_resolved(),
            self._no_delivery_in_flight(ContentQueueItem),
            # Explicit rescheduling grants another attempt without resetting
            # historical counts; only automatic failed-item retries are bounded.
            or_(ContentQueueItem.status == QueueItemStatus.SCHEDULED,
                ContentQueueItem.attempt_count < ContentQueueItem.max_attempts),
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
                    result = await session.execute(update(ContentQueueItem).where(
                        ContentQueueItem.id == item.id,
                        ContentQueueItem.status == item.status,
                        ContentQueueItem.scheduled_at == item.scheduled_at,
                        delivery_is_resolved(),
                    ).values(scheduled_at=next_allowed)
                        .execution_options(synchronize_session=False))
                    deferred += result.rowcount
                    continue

            if item.status == QueueItemStatus.SCHEDULED:
                claim_stmt = (
                    update(ContentQueueItem)
                    .where(
                        and_(
                            ContentQueueItem.id == item.id,
                            ContentQueueItem.status == QueueItemStatus.SCHEDULED,
                            or_(
                                ContentQueueItem.scheduled_at.is_(None),
                                ContentQueueItem.scheduled_at <= now,
                            ),
                            or_(
                                ContentQueueItem.locked_at.is_(None),
                                ContentQueueItem.locked_at < lock_expire,
                            ),
                        )
                    )
                    .values(
                        status=QueueItemStatus.PROCESSING,
                        locked_at=now,
                        locked_by=worker_name,
                        started_at=func.coalesce(ContentQueueItem.started_at, now),
                    )
                )
            else:
                claim_stmt = (
                    update(ContentQueueItem)
                    .where(
                        and_(
                            ContentQueueItem.id == item.id,
                            ContentQueueItem.status == QueueItemStatus.FAILED,
                            ContentQueueItem.next_attempt_at <= now,
                            or_(
                                ContentQueueItem.scheduled_at.is_(None),
                                ContentQueueItem.scheduled_at <= now,
                            ),
                            or_(
                                ContentQueueItem.locked_at.is_(None),
                                ContentQueueItem.locked_at < lock_expire,
                            ),
                        )
                    )
                    .values(
                        status=QueueItemStatus.PROCESSING,
                        locked_at=now,
                        locked_by=worker_name,
                        started_at=func.coalesce(ContentQueueItem.started_at, now),
                    )
                )

            claim_result = await session.execute(claim_stmt.where(
                enabled_rule_target,
                self._no_delivery_in_flight(item), delivery_is_resolved(),
                or_(ContentQueueItem.status == QueueItemStatus.SCHEDULED,
                    ContentQueueItem.attempt_count < ContentQueueItem.max_attempts),
            ).values(
                locked_by=uuid4().hex, last_error_type=DELIVERY_PREPARING,
                last_error=None, next_attempt_at=None,
                attempt_count=ContentQueueItem.attempt_count + 1,
            ).execution_options(synchronize_session=False))
            if int(claim_result.rowcount or 0) == 0:
                continue

            claimed_result = await session.execute(
                select(ContentQueueItem).where(ContentQueueItem.id == item.id).execution_options(populate_existing=True)
            )
            claimed = claimed_result.scalar_one_or_none()
            if claimed is not None:
                claimable.append(claimed)

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

    async def _transition(self, session: AsyncSession, item: ContentQueueItem, **values) -> bool:
        """Fence every worker write; the caller commits related facts together."""
        result = await session.execute(update(ContentQueueItem).where(
            owns_delivery(item),
        ).values(**values).execution_options(synchronize_session=False))
        if result.rowcount != 1:
            await session.rollback()
            return False
        await session.refresh(item)
        return True

    async def _defer(self, session, item, reason, code, *, terminal=False):
        if await self._transition(
            session, item,
            status=QueueItemStatus.FAILED if terminal else QueueItemStatus.SCHEDULED,
            last_error=reason, last_error_type=code, next_attempt_at=None,
            locked_at=None, locked_by=None,
            # Policy blocking is not a failed send attempt.
            attempt_count=max(0, item.attempt_count - 1),
        ):
            await session.commit()

    async def _mark_unknown(self, session: AsyncSession, item: ContentQueueItem):
        if not await self._transition(
            session, item, status=QueueItemStatus.FAILED,
            last_error=UNKNOWN_MESSAGE, last_error_type=DELIVERY_UNKNOWN,
            last_error_at=utcnow(), next_attempt_at=None, locked_at=None, locked_by=None,
        ):
            return
        await record_delivery_unknown(session, item)
        await session.commit()
        await event_bus.publish("queue_updated", {"action": DELIVERY_UNKNOWN, "queue_item_id": item.id})
        await event_bus.publish("notification_updated", {"source_type": "distribution_delivery"})

    async def _process_item(
        self,
        session: AsyncSession,
        item: ContentQueueItem,
        worker_name: str,
        *, manual: bool = False,
    ):
        """处理单个队列项：校验 → 去重 → 构建 → 推送 → 记录。"""
        # 1. 加载关联数据
        content_result = await session.execute(
            select(Content)
            .where(Content.id == item.content_id)
            .options(
                selectinload(Content.media_assets).selectinload(MediaAsset.variants)
            )
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
            await self._defer(session, item, "Target disabled or inaccessible", "target_unavailable")
            return

        # 2. 资格检查
        if not content or content.deleted_at is not None or content.review_status not in (
            ReviewStatus.APPROVED,
            ReviewStatus.AUTO_APPROVED,
        ) or content.status != ContentStatus.PARSE_SUCCESS:
            await self._defer(session, item, "Content not eligible", "content_not_eligible", terminal=True)
            return

        # 3. 去重检查
        dedupe_result = await session.execute(
            select(PushedRecord).where(
                and_(
                    PushedRecord.content_id == item.content_id,
                    PushedRecord.target_id == item.target_id,
                    PushedRecord.target_platform == item.target_platform,
                )
            ).limit(1)
        )
        if dedupe_result.scalar_one_or_none():
            await self._defer(session, item, "Already pushed (dedupe)", "already_pushed_dedupe", terminal=True)
            return

        # 4. 确定实际推送目标
        actual_target_id = item.target_id

        # 5. 构建推送 payload
        try:
            content_dict = await self._distributor._build_content_payload(
                content, rule, media_assets=content.media_assets,
                target_platform=item.target_platform,
            )
            push_service = get_push_service(item.target_platform)
        except Exception as error:
            await self._handle_failure(session, item, error)
            return

        # End the read transaction before rechecking controls that may have
        # changed while rendering. No external send has happened yet.
        await session.commit()
        await session.refresh(content, attribute_names=["review_status", "status", "deleted_at", "tags", "is_nsfw", "platform"])
        if bot_chat is not None:
            await session.refresh(bot_chat)
        if rule is not None:
            await session.refresh(rule)
        target_enabled = (await session.execute(select(DistributionTarget.enabled).where(
            DistributionTarget.rule_id == item.rule_id,
            DistributionTarget.bot_chat_id == item.bot_chat_id,
        ))).scalar_one_or_none()
        reason, code = None, None
        if not rule or not rule.enabled or not target_enabled or not bot_chat.enabled or not bot_chat.is_accessible:
            reason, code = "Rule or target disabled", "rule_or_target_disabled"
        elif content.deleted_at is not None or content.status != ContentStatus.PARSE_SUCCESS or content.review_status not in (ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED):
            reason, code = "Content no longer eligible", "content_not_eligible"
        else:
            decision = should_distribute(content=content, rule=rule, bot_chat=bot_chat)
            if rule.approval_required and content.review_status == ReviewStatus.AUTO_APPROVED:
                reason, code = "Manual approval now required", "approval_required"
            elif decision.bucket != DECISION_WILL_PUSH:
                reason, code = decision.reason, decision.reason_code
            elif decision.target_id != actual_target_id:
                # A changed destination needs enqueue to acquire the correct
                # target lease and deduplication identity before another send.
                reason, code = "Target routing changed; refresh queue", "target_routing_changed"
        policies = [await AutomationPolicyService().aggregation_delivery(content)]
        if not manual:
            policies.append(await AutomationPolicyService().distribution_worker_poll())
        for policy in policies:
            if not policy.allowed:
                reason, code = policy.reason, policy.code
        if reason:
            await self._defer(session, item, reason, code)
            return

        # Persist the send boundary before IO. Neither a lost response nor a
        # process death after this commit proves the platform did not accept it.
        if not await self._transition(session, item, last_error_type=DELIVERY_SENDING):
            return
        await session.commit()
        remaining = max(0, (item.locked_at + timedelta(seconds=LOCK_TIMEOUT) - utcnow()).total_seconds())
        try:
            message_id = await asyncio.wait_for(
                push_service.push(content_dict, actual_target_id), timeout=remaining,
            )
        except QQRateLimited as exc:
            if await self._transition(
                session, item, status=QueueItemStatus.SCHEDULED,
                scheduled_at=datetime.utcfromtimestamp(exc.retry_at),
                last_error=str(exc), last_error_type="target_rate_limited",
                locked_at=None, locked_by=None,
                attempt_count=max(0, item.attempt_count - 1),
            ):
                await session.commit()
            return
        except asyncio.CancelledError:
            await self._mark_unknown(session, item)
            raise
        except Exception:
            await self._mark_unknown(session, item)
            return

        if not message_id:
            await self._mark_unknown(session, item)
            return

        # 7. 成功处理
        now = utcnow()
        if not await self._transition(
            session, item, status=QueueItemStatus.SUCCESS,
            message_id=str(message_id), completed_at=now,
            last_error=None, last_error_type=None, last_error_at=None,
            next_attempt_at=None, locked_at=None, locked_by=None,
        ):
            return

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
            await session.execute(update(BotChat).where(BotChat.id == bot_chat.id).values(
                total_pushed=BotChat.total_pushed + 1, last_pushed_at=now,
            ))

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
        """Retry only failures before the durable send boundary."""
        now = utcnow()
        next_attempt = (
            now + timedelta(seconds=min(60 * (2 ** item.attempt_count), 3600))
            if item.attempt_count < item.max_attempts else None
        )
        if not await self._transition(
            session, item, status=QueueItemStatus.FAILED,
            last_error="发送准备失败，尚未调用发送服务。", last_error_type=type(error).__name__,
            last_error_at=now, locked_at=None, locked_by=None, next_attempt_at=next_attempt,
        ):
            return
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
