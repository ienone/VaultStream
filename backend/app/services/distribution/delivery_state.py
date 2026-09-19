"""Durable delivery phases and fencing, using the existing queue lock fields."""
from datetime import datetime, timedelta
from typing import Literal

from sqlalchemy import and_, or_, select, update
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.time_utils import utcnow
from app.models import BotChat, ContentQueueItem, NotificationMessage, PushedRecord, QueueItemStatus
from app.utils.datetime_utils import normalize_datetime_for_db


DELIVERY_PREPARING = "delivery_preparing"
DELIVERY_SENDING = "delivery_sending"
DELIVERY_UNKNOWN = "delivery_unknown"
DELIVERY_NOT_SENT = "delivery_not_sent"
LOCK_TIMEOUT = 600
UNKNOWN_MESSAGE = "发送结果未知，请先到目标会话核对；系统不会自动重发。"


def delivery_is_resolved():
    return or_(
        ContentQueueItem.last_error_type.is_(None),
        ContentQueueItem.last_error_type != DELIVERY_UNKNOWN,
    )


def owns_delivery(item: ContentQueueItem):
    """A claim token is unique per attempt, including manual and restarted workers."""
    return and_(
        ContentQueueItem.id == item.id,
        ContentQueueItem.status == QueueItemStatus.PROCESSING,
        ContentQueueItem.locked_by == item.locked_by,
        ContentQueueItem.locked_at == item.locked_at,
        ContentQueueItem.locked_at > utcnow() - timedelta(seconds=LOCK_TIMEOUT),
    )


async def record_delivery_unknown(db: AsyncSession, item: ContentQueueItem) -> None:
    """Persist the actionable inbox projection in the queue transition transaction."""
    now = utcnow()
    statement = sqlite_insert(NotificationMessage).values(
        dedupe_key=f"delivery-unknown:{item.id}",
        category="task",
        severity="attention",
        title="发送结果待核对",
        body=UNKNOWN_MESSAGE,
        route=f"/automation/distribution?review_item={item.id}",
        source_type="distribution_delivery",
        source_id=str(item.id),
        payload={"queue_item_id": item.id, "content_id": item.content_id,
                 "target_platform": item.target_platform, "target_id": item.target_id,
                 "status": DELIVERY_UNKNOWN},
        first_occurred_at=now,
        last_occurred_at=now,
    )
    await db.execute(statement.on_conflict_do_update(
        index_elements=[NotificationMessage.dedupe_key],
        set_={"payload": statement.excluded.payload, "read_at": None,
              "dismissed_at": None, "last_occurred_at": now, "updated_at": now},
    ))


async def resolve_delivery_notification(db: AsyncSession, item_id: int) -> None:
    now = utcnow()
    await db.execute(update(NotificationMessage).where(
        NotificationMessage.dedupe_key == f"delivery-unknown:{item_id}",
    ).values(read_at=now, dismissed_at=now, updated_at=now))


async def reconcile_delivery(
    db: AsyncSession,
    item_id: int,
    *,
    outcome: Literal["delivered", "not_sent"],
    observed_error_at: datetime,
    message_id: str | None,
) -> ContentQueueItem:
    """Apply a fresh human observation; the caller commits, never sends."""
    result = await db.execute(update(ContentQueueItem).where(
        ContentQueueItem.id == item_id,
        ContentQueueItem.status == QueueItemStatus.FAILED,
        ContentQueueItem.last_error_type == DELIVERY_UNKNOWN,
        ContentQueueItem.last_error_at == normalize_datetime_for_db(observed_error_at),
    ).values(last_error_type=DELIVERY_UNKNOWN).execution_options(synchronize_session=False))
    if result.rowcount != 1:
        raise ValueError("待核对记录已变化，请刷新后重新核对。")
    item = (await db.execute(select(ContentQueueItem).where(
        ContentQueueItem.id == item_id,
    ).execution_options(populate_existing=True))).scalar_one()
    now = utcnow()
    if outcome == "delivered":
        existing = (await db.execute(select(PushedRecord).where(
            PushedRecord.content_id == item.content_id,
            PushedRecord.target_id == item.target_id,
        ))).scalar_one_or_none()
        if existing and (existing.target_platform != item.target_platform or existing.message_id != message_id):
            raise ValueError("已有不同的发送记录，请核对目标和消息 ID。")
        if existing is None:
            db.add(PushedRecord(content_id=item.content_id,
                target_platform=item.target_platform, target_id=item.target_id,
                message_id=message_id, push_status="success", pushed_at=now))
            await db.execute(update(BotChat).where(BotChat.id == item.bot_chat_id).values(
                total_pushed=BotChat.total_pushed + 1, last_pushed_at=now,
            ))
        item.status = QueueItemStatus.SUCCESS
        item.message_id = message_id
        item.completed_at = now
        item.last_error_type = "delivery_confirmed"
        item.last_error = "已人工核对送达；记录时间为核对时间。"
    else:
        # Clearing the unknown result also releases the peer-send exclusion.
        # Stop already queued attempts for this destination under the same
        # writer lock, so reconciliation alone cannot authorize another send.
        await db.execute(update(ContentQueueItem).where(
            ContentQueueItem.id != item.id,
            ContentQueueItem.content_id == item.content_id,
            ContentQueueItem.target_platform == item.target_platform,
            ContentQueueItem.target_id == item.target_id,
            delivery_is_resolved(),
            or_(
                ContentQueueItem.status == QueueItemStatus.SCHEDULED,
                and_(
                    ContentQueueItem.status == QueueItemStatus.FAILED,
                    ContentQueueItem.next_attempt_at.is_not(None),
                ),
            ),
        ).values(
            status=QueueItemStatus.FAILED,
            next_attempt_at=None, locked_at=None, locked_by=None,
            last_error_type=DELIVERY_NOT_SENT,
            last_error="同一内容在该目标已核对未发送，请重新排期。",
            last_error_at=now, approved_by="manual_delivery_reconciliation",
        ).execution_options(synchronize_session=False))
        item.last_error_type = DELIVERY_NOT_SENT
        item.last_error = "已人工核对未发送，可单独重新排期。"
        item.attempt_count = 0
    item.next_attempt_at = None
    item.last_error_at = now
    item.approved_by = "manual_delivery_reconciliation"
    await resolve_delivery_notification(db, item.id)
    return item


async def recover_expired_deliveries(db: AsyncSession) -> int:
    """Only a persisted pre-send phase is safe to retry; legacy locks are unknown."""
    now = utcnow()
    expired = and_(
        ContentQueueItem.status == QueueItemStatus.PROCESSING,
        or_(ContentQueueItem.locked_at.is_(None),
            ContentQueueItem.locked_at <= now - timedelta(seconds=LOCK_TIMEOUT)),
    )
    items = (await db.execute(select(ContentQueueItem).where(expired))).scalars().all()
    changed = 0
    for item in items:
        safe_to_retry = item.last_error_type == DELIVERY_PREPARING
        result = await db.execute(update(ContentQueueItem).where(
            ContentQueueItem.id == item.id,
            expired,
            ContentQueueItem.locked_by == item.locked_by,
            ContentQueueItem.last_error_type == item.last_error_type,
        ).values(
            status=QueueItemStatus.FAILED,
            locked_at=None, locked_by=None,
            next_attempt_at=now if safe_to_retry and item.attempt_count < item.max_attempts else None,
            last_error_type="delivery_preparation_interrupted" if safe_to_retry else DELIVERY_UNKNOWN,
            last_error="发送准备中断，尚未调用发送服务。" if safe_to_retry else UNKNOWN_MESSAGE,
            last_error_at=now,
        ).execution_options(synchronize_session=False))
        if result.rowcount != 1:
            continue
        if not safe_to_retry:
            await record_delivery_unknown(db, item)
        changed += 1
    await db.commit()
    return changed
