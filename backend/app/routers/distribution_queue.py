"""
分发队列管理 API（ContentQueueItem 架构）
"""
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Body, Depends, HTTPException, Query
from sqlalchemy import and_, func, select, not_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import require_api_token
from app.core.events import event_bus
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.models import Content, ContentQueueItem, QueueItemStatus
from app.distribution.queue_worker import get_queue_worker
from app.schemas import (
    BatchQueueRetryRequest,
    ContentQueueItemListResponse,
    ContentQueueItemResponse,
    EnqueueContentRequest,
    QueueItemRetryRequest,
    QueueStatsResponse,
)

router = APIRouter(prefix="/distribution-queue", tags=["distribution-queue"])


def _as_utc(dt: Optional[datetime]) -> Optional[datetime]:
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _to_queue_item_response(item: ContentQueueItem, content: Optional[Content] = None) -> ContentQueueItemResponse:
    return ContentQueueItemResponse(
        id=item.id,
        content_id=item.content_id,
        title=(content.title if content else None),
        tags=((content.tags or []) if content else []),
        is_nsfw=bool(content.is_nsfw) if content else False,
        cover_url=(content.cover_url if content else None),
        author_name=(content.author_name if content else None),
        rule_id=item.rule_id,
        bot_chat_id=item.bot_chat_id,
        target_platform=item.target_platform,
        target_id=item.target_id,
        status=item.status.value if hasattr(item.status, "value") else str(item.status),
        priority=item.priority or 0,
        scheduled_at=_as_utc(item.scheduled_at),
        needs_approval=bool(item.needs_approval),
        approved_at=_as_utc(item.approved_at),
        attempt_count=item.attempt_count or 0,
        max_attempts=item.max_attempts or 3,
        next_attempt_at=_as_utc(item.next_attempt_at),
        message_id=item.message_id,
        last_error=item.last_error,
        last_error_type=item.last_error_type,
        last_error_at=_as_utc(item.last_error_at),
        started_at=_as_utc(item.started_at),
        completed_at=_as_utc(item.completed_at),
        created_at=_as_utc(item.created_at) or datetime.now(timezone.utc),
        updated_at=_as_utc(item.updated_at) or datetime.now(timezone.utc),
    )


def _build_status_conditions(status: Optional[str]):
    if not status:
        return []

    if status == "pending_review":
        return [
            ContentQueueItem.status == QueueItemStatus.PENDING,
            ContentQueueItem.needs_approval == True,
            ContentQueueItem.approved_at.is_(None),
        ]

    if status == "will_push":
        return [
            ContentQueueItem.status.in_(
                [
                    QueueItemStatus.PENDING,
                    QueueItemStatus.SCHEDULED,
                    QueueItemStatus.PROCESSING,
                    QueueItemStatus.FAILED,
                ]
            ),
            not_(
                and_(
                    ContentQueueItem.status == QueueItemStatus.PENDING,
                    ContentQueueItem.needs_approval == True,
                    ContentQueueItem.approved_at.is_(None),
                )
            ),
        ]

    if status == "filtered":
        return [ContentQueueItem.status.in_([QueueItemStatus.CANCELED, QueueItemStatus.SKIPPED])]

    if status == "pushed":
        return [ContentQueueItem.status == QueueItemStatus.SUCCESS]

    try:
        return [ContentQueueItem.status == QueueItemStatus(status)]
    except Exception:
        raise HTTPException(status_code=400, detail=f"Invalid status: {status}")


@router.get("/stats", response_model=QueueStatsResponse)
async def get_queue_stats(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取队列统计信息。"""
    grouped_result = await db.execute(
        select(
            ContentQueueItem.status,
            ContentQueueItem.needs_approval,
            ContentQueueItem.approved_at,
            func.count(ContentQueueItem.id),
        ).group_by(
            ContentQueueItem.status,
            ContentQueueItem.needs_approval,
            ContentQueueItem.approved_at,
        )
    )

    stats = {
        "will_push": 0,
        "filtered": 0,
        "pending_review": 0,
        "pushed": 0,
        "total": 0,
    }

    for status, needs_approval, approved_at, count in grouped_result.all():
        count_int = int(count or 0)
        if status == QueueItemStatus.SUCCESS:
            bucket = "pushed"
        elif status in (QueueItemStatus.SKIPPED, QueueItemStatus.CANCELED):
            bucket = "filtered"
        elif status == QueueItemStatus.PENDING and bool(needs_approval) and approved_at is None:
            bucket = "pending_review"
        else:
            # 其余状态（含 FAILED）统一视为待推送阶段，便于看板聚合处理。
            bucket = "will_push"

        stats[bucket] += count_int
        stats["total"] += count_int

    now = utcnow()
    due_result = await db.execute(
        select(func.count(ContentQueueItem.id)).where(
            and_(
                ContentQueueItem.status == QueueItemStatus.SCHEDULED,
                ContentQueueItem.scheduled_at <= now,
            )
        )
    )
    due_now = int(due_result.scalar() or 0)

    return QueueStatsResponse(
        will_push=stats["will_push"],
        filtered=stats["filtered"],
        pending_review=stats["pending_review"],
        pushed=stats["pushed"],
        total=stats["total"],
        due_now=due_now,
    )


@router.get("/items", response_model=ContentQueueItemListResponse)
async def list_queue_items(
    status: Optional[str] = Query(None, description="状态过滤（支持别名 will_push/filtered/pending_review/pushed）"),
    content_id: Optional[int] = Query(None, description="按内容ID过滤"),
    rule_id: Optional[int] = Query(None, description="按规则ID过滤"),
    bot_chat_id: Optional[int] = Query(None, description="按BotChat ID过滤"),
    page: int = Query(1, ge=1, description="页码"),
    size: int = Query(50, ge=1, le=200, description="每页数量"),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取队列项列表（分页）。"""
    conditions = []

    conditions.extend(_build_status_conditions(status))

    if content_id is not None:
        conditions.append(ContentQueueItem.content_id == content_id)
    if rule_id is not None:
        conditions.append(ContentQueueItem.rule_id == rule_id)
    if bot_chat_id is not None:
        conditions.append(ContentQueueItem.bot_chat_id == bot_chat_id)

    where_clause = and_(*conditions) if conditions else True

    count_result = await db.execute(
        select(func.count(ContentQueueItem.id)).where(where_clause)
    )
    total = int(count_result.scalar() or 0)

    offset = (page - 1) * size
    result = await db.execute(
        select(ContentQueueItem, Content)
        .join(Content, Content.id == ContentQueueItem.content_id, isouter=True)
        .where(where_clause)
        .order_by(ContentQueueItem.created_at.desc())
        .offset(offset)
        .limit(size)
    )
    rows = result.all()

    return ContentQueueItemListResponse(
        items=[_to_queue_item_response(item, content) for item, content in rows],
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
    """获取单个队列项。"""
    result = await db.execute(
        select(ContentQueueItem, Content)
        .join(Content, Content.id == ContentQueueItem.content_id, isouter=True)
        .where(ContentQueueItem.id == item_id)
    )
    row = result.first()
    item = row[0] if row else None
    content = row[1] if row else None
    if not item:
        raise HTTPException(status_code=404, detail="Queue item not found")
    return _to_queue_item_response(item, content)


@router.post("/items/{item_id}/push-now", response_model=ContentQueueItemResponse)
async def push_queue_item_now(
    item_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """立即执行单个队列项推送（用于手动触发）。"""
    result = await db.execute(
        select(ContentQueueItem).where(ContentQueueItem.id == item_id)
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Queue item not found")

    worker = get_queue_worker()
    try:
        await worker.process_item_now(item_id, worker_name="api-manual")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    refreshed = await db.execute(
        select(ContentQueueItem, Content)
        .join(Content, Content.id == ContentQueueItem.content_id, isouter=True)
        .where(ContentQueueItem.id == item_id)
    )
    row = refreshed.first()
    item = row[0] if row else None
    content = row[1] if row else None
    if not item:
        raise HTTPException(status_code=404, detail="Queue item not found")
    return _to_queue_item_response(item, content)


@router.post("/enqueue/{content_id}")
async def enqueue_content_endpoint(
    content_id: int,
    request: EnqueueContentRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """手动将内容入队。"""
    result = await db.execute(select(Content).where(Content.id == content_id))
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Content not found")

    from app.distribution.queue_service import enqueue_content

    enqueued_count = await enqueue_content(content_id, session=db, force=request.force)
    logger.info(f"手动入队: content_id={content_id}, enqueued={enqueued_count}")
    await event_bus.publish("queue_updated", {
        "action": "manual_enqueue",
        "content_id": content_id,
        "items_changed": enqueued_count,
        "timestamp": utcnow().isoformat(),
    })
    return {"status": "ok", "enqueued_count": enqueued_count}


@router.post("/items/{item_id}/retry", response_model=ContentQueueItemResponse)
async def retry_queue_item(
    item_id: int,
    request: QueueItemRetryRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """重试单个队列项。"""
    result = await db.execute(select(ContentQueueItem).where(ContentQueueItem.id == item_id))
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

    await event_bus.publish("queue_updated", {
        "action": "retry_item",
        "queue_item_id": item_id,
        "status": item.status.value,
        "timestamp": utcnow().isoformat(),
    })
    return ContentQueueItemResponse.model_validate(item)


@router.post("/items/{item_id}/cancel")
async def cancel_queue_item(
    item_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """取消单个队列项。"""
    result = await db.execute(select(ContentQueueItem).where(ContentQueueItem.id == item_id))
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Queue item not found")

    item.status = QueueItemStatus.CANCELED
    item.locked_at = None
    item.locked_by = None

    await db.commit()

    await event_bus.publish("queue_updated", {
        "action": "cancel_item",
        "queue_item_id": item_id,
        "timestamp": utcnow().isoformat(),
    })
    return {"status": "canceled", "id": item_id}


@router.post("/batch-retry")
async def batch_retry_queue_items(
    request: BatchQueueRetryRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """批量重试队列项。"""
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

    await event_bus.publish("queue_updated", {
        "action": "batch_retry",
        "retried_count": len(retried_ids),
        "queue_item_ids": retried_ids,
        "timestamp": utcnow().isoformat(),
    })
    return {"retried_count": len(retried_ids), "item_ids": retried_ids}


@router.post("/content/{content_id}/status")
async def set_content_queue_status(
    content_id: int,
    payload: dict = Body(default={}),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """按内容维度设置队列状态（供前端交互）。"""
    target_status = str(payload.get("status") or "").strip().lower()
    now = utcnow()

    result = await db.execute(select(ContentQueueItem).where(ContentQueueItem.content_id == content_id))
    items = result.scalars().all()

    if target_status == "will_push":
        changed = 0
        for item in items:
            if item.status in (QueueItemStatus.SUCCESS, QueueItemStatus.CANCELED):
                continue
            item.status = QueueItemStatus.SCHEDULED
            item.needs_approval = False
            item.scheduled_at = now
            item.next_attempt_at = None
            changed += 1
        await db.commit()
        await event_bus.publish("queue_updated", {
            "action": "content_status_will_push",
            "content_id": content_id,
            "items_changed": changed,
            "timestamp": now.isoformat(),
        })
        return {"status": "ok", "moved": changed}

    if target_status == "filtered":
        changed = 0
        for item in items:
            if item.status == QueueItemStatus.SUCCESS:
                continue
            item.status = QueueItemStatus.CANCELED
            item.locked_at = None
            item.locked_by = None
            changed += 1
        await db.commit()
        await event_bus.publish("queue_updated", {
            "action": "content_status_filtered",
            "content_id": content_id,
            "items_changed": changed,
            "timestamp": now.isoformat(),
        })
        return {"status": "ok", "moved": changed}

    raise HTTPException(status_code=400, detail="Unsupported status")


@router.post("/content/{content_id}/reorder")
async def reorder_content_queue(
    content_id: int,
    payload: dict = Body(default={}),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """按内容维度重排（通过优先级提升实现）。"""
    index = int(payload.get("index") or 0)
    boost = max(1, 1000 - index)

    result = await db.execute(
        select(ContentQueueItem)
        .where(ContentQueueItem.content_id == content_id)
        .order_by(ContentQueueItem.priority.desc(), ContentQueueItem.id.asc())
    )
    items = result.scalars().all()

    changed = 0
    for item in items:
        if item.status in (QueueItemStatus.SCHEDULED, QueueItemStatus.PROCESSING, QueueItemStatus.PENDING):
            item.priority = max(item.priority, boost)
            changed += 1

    await db.commit()
    await event_bus.publish("queue_updated", {
        "action": "content_reorder",
        "content_id": content_id,
        "items_changed": changed,
        "timestamp": utcnow().isoformat(),
    })
    return {"status": "ok", "changed": changed}


@router.post("/content/{content_id}/push-now")
async def push_now_content_queue(
    content_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """将内容相关队列项立即推送。"""
    now = utcnow()
    result = await db.execute(select(ContentQueueItem).where(ContentQueueItem.content_id == content_id))
    items = result.scalars().all()

    changed = 0
    for item in items:
        if item.status in (QueueItemStatus.SCHEDULED, QueueItemStatus.FAILED):
            item.status = QueueItemStatus.SCHEDULED
            item.scheduled_at = now
            item.next_attempt_at = None
            changed += 1

    await db.commit()
    await event_bus.publish("queue_updated", {
        "action": "content_push_now",
        "content_id": content_id,
        "items_changed": changed,
        "timestamp": now.isoformat(),
    })
    return {"status": "ok", "changed": changed}


@router.post("/content/{content_id}/schedule")
async def schedule_content_queue(
    content_id: int,
    payload: dict = Body(default={}),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """按内容维度更新排期时间。"""
    raw = payload.get("scheduled_at")
    if not raw:
        raise HTTPException(status_code=400, detail="scheduled_at is required")
    try:
        scheduled_at = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid scheduled_at")

    result = await db.execute(select(ContentQueueItem).where(ContentQueueItem.content_id == content_id))
    items = result.scalars().all()

    changed = 0
    for item in items:
        if item.status in (QueueItemStatus.SCHEDULED, QueueItemStatus.FAILED, QueueItemStatus.PENDING):
            item.status = QueueItemStatus.SCHEDULED
            item.scheduled_at = scheduled_at
            item.next_attempt_at = None
            changed += 1

    await db.commit()
    await event_bus.publish("queue_updated", {
        "action": "content_schedule",
        "content_id": content_id,
        "items_changed": changed,
        "timestamp": utcnow().isoformat(),
    })
    return {"status": "ok", "changed": changed}


@router.post("/content/batch-push-now")
async def batch_push_now_content_queue(
    payload: dict = Body(default={}),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """批量立即推送（内容维度）。"""
    content_ids = [int(cid) for cid in (payload.get("content_ids") or [])]
    if not content_ids:
        return {"status": "ok", "changed": 0}

    now = utcnow()
    result = await db.execute(
        select(ContentQueueItem).where(ContentQueueItem.content_id.in_(content_ids))
    )
    items = result.scalars().all()

    changed = 0
    for item in items:
        if item.status in (QueueItemStatus.SCHEDULED, QueueItemStatus.FAILED):
            item.status = QueueItemStatus.SCHEDULED
            item.scheduled_at = now
            item.next_attempt_at = None
            changed += 1

    await db.commit()
    await event_bus.publish("queue_updated", {
        "action": "content_batch_push_now",
        "content_ids": content_ids,
        "items_changed": changed,
        "timestamp": now.isoformat(),
    })
    return {"status": "ok", "changed": changed}


@router.post("/content/batch-reschedule")
async def batch_reschedule_content_queue(
    payload: dict = Body(default={}),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """批量排期（内容维度）。"""
    content_ids = [int(cid) for cid in (payload.get("content_ids") or [])]
    raw_start = payload.get("start_time")
    interval_seconds = int(payload.get("interval_seconds") or 300)

    if not content_ids or not raw_start:
        return {"status": "ok", "changed": 0}

    try:
        start_time = datetime.fromisoformat(str(raw_start).replace("Z", "+00:00"))
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid start_time")

    result = await db.execute(
        select(ContentQueueItem).where(ContentQueueItem.content_id.in_(content_ids))
    )
    grouped = {}
    for item in result.scalars().all():
        grouped.setdefault(item.content_id, []).append(item)

    changed = 0
    for idx, content_id in enumerate(content_ids):
        scheduled = start_time + timedelta(seconds=interval_seconds * idx)
        for item in grouped.get(content_id, []):
            if item.status in (QueueItemStatus.SCHEDULED, QueueItemStatus.FAILED, QueueItemStatus.PENDING):
                item.status = QueueItemStatus.SCHEDULED
                item.scheduled_at = scheduled
                item.next_attempt_at = None
                changed += 1

    await db.commit()
    await event_bus.publish("queue_updated", {
        "action": "content_batch_reschedule",
        "content_ids": content_ids,
        "items_changed": changed,
        "timestamp": utcnow().isoformat(),
    })
    return {"status": "ok", "changed": changed}


@router.post("/content/merge-group")
async def merge_group_content_queue(
    payload: dict = Body(default={}),
    _: None = Depends(require_api_token),
):
    """队列模型不需要显式 merge-group，保留语义化成功响应。"""
    return {
        "status": "ok",
        "message": "merge-group is not required in ContentQueueItem model",
        "content_ids": payload.get("content_ids") or [],
    }
