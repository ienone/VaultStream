"""
分发队列管理 API（新架构：ContentQueueItem）
"""
from typing import Optional, List
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, func, and_, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import require_api_token
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.models import ContentQueueItem, QueueItemStatus, Content
from app.schemas import (
    ContentQueueItemResponse,
    ContentQueueItemListResponse,
    QueueStatsResponse,
    EnqueueContentRequest,
    QueueItemRetryRequest,
    BatchQueueRetryRequest,
)

router = APIRouter(prefix="/distribution-queue", tags=["distribution-queue"])


@router.get("/stats", response_model=QueueStatsResponse)
async def get_queue_stats(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取队列统计信息"""
    counts = {}
    for status in QueueItemStatus:
        result = await db.execute(
            select(func.count(ContentQueueItem.id)).where(
                ContentQueueItem.status == status
            )
        )
        counts[status.value] = result.scalar() or 0

    now = utcnow()
    due_result = await db.execute(
        select(func.count(ContentQueueItem.id)).where(
            and_(
                ContentQueueItem.status == QueueItemStatus.SCHEDULED,
                ContentQueueItem.scheduled_at <= now,
            )
        )
    )
    due_now = due_result.scalar() or 0

    return QueueStatsResponse(
        pending=counts.get("pending", 0),
        scheduled=counts.get("scheduled", 0),
        processing=counts.get("processing", 0),
        success=counts.get("success", 0),
        failed=counts.get("failed", 0),
        skipped=counts.get("skipped", 0),
        canceled=counts.get("canceled", 0),
        total=sum(counts.values()),
        due_now=due_now,
    )


@router.get("/items", response_model=ContentQueueItemListResponse)
async def list_queue_items(
    status: Optional[str] = Query(None, description="按状态过滤"),
    content_id: Optional[int] = Query(None, description="按内容ID过滤"),
    rule_id: Optional[int] = Query(None, description="按规则ID过滤"),
    bot_chat_id: Optional[int] = Query(None, description="按BotChat ID过滤"),
    page: int = Query(1, ge=1, description="页码"),
    size: int = Query(50, ge=1, le=200, description="每页数量"),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取队列项列表（分页）"""
    conditions = []
    if status is not None:
        conditions.append(ContentQueueItem.status == status)
    if content_id is not None:
        conditions.append(ContentQueueItem.content_id == content_id)
    if rule_id is not None:
        conditions.append(ContentQueueItem.rule_id == rule_id)
    if bot_chat_id is not None:
        conditions.append(ContentQueueItem.bot_chat_id == bot_chat_id)

    where_clause = and_(*conditions) if conditions else True

    # 总数
    count_result = await db.execute(
        select(func.count(ContentQueueItem.id)).where(where_clause)
    )
    total = count_result.scalar() or 0

    # 分页查询
    offset = (page - 1) * size
    result = await db.execute(
        select(ContentQueueItem)
        .where(where_clause)
        .order_by(ContentQueueItem.created_at.desc())
        .offset(offset)
        .limit(size)
    )
    items = result.scalars().all()

    return ContentQueueItemListResponse(
        items=[ContentQueueItemResponse.model_validate(item) for item in items],
        total=total,
        page=page,
        size=size,
        has_more=(offset + size) < total,
    )


@router.get("/items/{item_id}", response_model=ContentQueueItemResponse)
async def get_queue_item(
    item_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取单个队列项"""
    result = await db.execute(
        select(ContentQueueItem).where(ContentQueueItem.id == item_id)
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Queue item not found")
    return ContentQueueItemResponse.model_validate(item)


@router.post("/enqueue/{content_id}")
async def enqueue_content_endpoint(
    content_id: int,
    request: EnqueueContentRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """手动将内容入队"""
    # 验证内容存在
    result = await db.execute(
        select(Content).where(Content.id == content_id)
    )
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Content not found")

    from app.distribution.queue_service import enqueue_content

    enqueued_count = await enqueue_content(
        content_id, session=db, force=request.force
    )
    logger.info(f"手动入队: content_id={content_id}, enqueued={enqueued_count}")
    return {"status": "ok", "enqueued_count": enqueued_count}


@router.post("/items/{item_id}/retry", response_model=ContentQueueItemResponse)
async def retry_queue_item(
    item_id: int,
    request: QueueItemRetryRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """重试队列项"""
    result = await db.execute(
        select(ContentQueueItem).where(ContentQueueItem.id == item_id)
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Queue item not found")

    item.status = QueueItemStatus.SCHEDULED
    item.locked_at = None
    item.locked_by = None
    item.next_attempt_at = None
    item.scheduled_at = utcnow()
    if request.reset_attempts:
        item.attempt_count = 0

    await db.commit()
    await db.refresh(item)

    logger.info(f"队列项重试: id={item_id}, reset_attempts={request.reset_attempts}")
    return ContentQueueItemResponse.model_validate(item)


@router.post("/items/{item_id}/cancel")
async def cancel_queue_item(
    item_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """取消队列项"""
    result = await db.execute(
        select(ContentQueueItem).where(ContentQueueItem.id == item_id)
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Queue item not found")

    item.status = QueueItemStatus.CANCELED
    item.locked_at = None
    item.locked_by = None

    await db.commit()

    logger.info(f"队列项已取消: id={item_id}")
    return {"status": "canceled", "id": item_id}


@router.post("/batch-retry")
async def batch_retry_queue_items(
    request: BatchQueueRetryRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """批量重试队列项"""
    conditions = []
    if request.item_ids:
        conditions.append(ContentQueueItem.id.in_(request.item_ids))
    else:
        conditions.append(ContentQueueItem.status == request.status_filter)

    result = await db.execute(
        select(ContentQueueItem)
        .where(and_(*conditions))
        .limit(request.limit)
    )
    items = result.scalars().all()

    now = utcnow()
    retried_ids = []
    for item in items:
        item.status = QueueItemStatus.SCHEDULED
        item.locked_at = None
        item.locked_by = None
        item.next_attempt_at = None
        item.scheduled_at = now
        retried_ids.append(item.id)

    await db.commit()

    logger.info(f"批量重试队列项: count={len(retried_ids)}, ids={retried_ids}")
    return {"retried_count": len(retried_ids), "item_ids": retried_ids}
