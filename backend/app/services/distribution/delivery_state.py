"""Durable delivery phases and fencing, using the existing queue lock fields."""
from datetime import timedelta

from sqlalchemy import and_, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.time_utils import utcnow
from app.models import ContentQueueItem, QueueItemStatus


DELIVERY_PREPARING = "delivery_preparing"
DELIVERY_SENDING = "delivery_sending"
DELIVERY_UNKNOWN = "delivery_unknown"
LOCK_TIMEOUT = 600
UNKNOWN_MESSAGE = "未收到发送回执，已停止自动重试。"


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
        changed += 1
    await db.commit()
    return changed
