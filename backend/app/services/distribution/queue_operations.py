"""Shared manual queue transitions for item, content and batch API operations."""

from datetime import datetime

from sqlalchemy import update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import ContentQueueItem, QueueItemStatus
from app.services.distribution.delivery_state import delivery_is_resolved
from app.services.distribution.receipt_policy import EXPLICIT_PUSH


class QueueEditConflict(ValueError):
    pass


async def lock_item_for_edit(db: AsyncSession, item: ContentQueueItem) -> None:
    """Serialize with worker claims; never clear an active or unknown send."""
    result = await db.execute(
        update(ContentQueueItem).where(
            ContentQueueItem.id == item.id,
            ContentQueueItem.status == item.status,
            ContentQueueItem.status != QueueItemStatus.PROCESSING,
            delivery_is_resolved(),
        ).values(status=item.status).execution_options(synchronize_session=False)
    )
    if result.rowcount != 1:
        raise QueueEditConflict("队列项正在发送、未收到发送回执或状态已变化，请刷新后逐条处理。")


def schedule_item(item: ContentQueueItem, *, at: datetime, clear_receipt: bool = False) -> None:
    """Caller holds the edit lock. Only explicit repush clears the receipt."""
    item.status = QueueItemStatus.SCHEDULED
    item.approved_by = EXPLICIT_PUSH
    item.scheduled_at = at
    item.locked_at = None
    item.locked_by = None
    item.next_attempt_at = None
    item.last_error = None
    item.last_error_type = None
    item.last_error_at = None
    if clear_receipt:
        item.message_id = None


def filter_item(item: ContentQueueItem, *, reason: str, error_type: str, at: datetime) -> None:
    item.status = QueueItemStatus.FAILED
    item.locked_at = None
    item.locked_by = None
    item.next_attempt_at = None
    item.last_error = reason
    item.last_error_type = error_type
    item.last_error_at = at


async def cancel_items(db: AsyncSession, item_ids: list[int], *, at: datetime) -> list[int]:
    """Cancel one selection atomically without loading content or media."""
    ids = set(item_ids)
    result = await db.execute(
        update(ContentQueueItem).where(
            ContentQueueItem.id.in_(ids),
            ContentQueueItem.status.in_([QueueItemStatus.SCHEDULED, QueueItemStatus.FAILED]),
            delivery_is_resolved(),
        ).values(
            status=QueueItemStatus.FAILED,
            locked_at=None, locked_by=None, next_attempt_at=None,
            last_error="已取消发送", last_error_type="manual_canceled", last_error_at=at,
        ).returning(ContentQueueItem.id).execution_options(synchronize_session=False)
    )
    canceled = list(result.scalars())
    if set(canceled) != ids:
        await db.rollback()
        raise QueueEditConflict("所选记录已变化，请刷新列表后重试。")
    await db.commit()
    return canceled
