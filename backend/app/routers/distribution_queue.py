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
from app.models import Content, ContentQueueItem, QueueItemStatus, DistributionRule, PushedRecord
from app.tasks import DistributionQueueWorker
from app.services.distribution.scheduler import compute_auto_scheduled_at

def get_queue_worker():
    return DistributionQueueWorker()
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
        source_platform=(content.platform.value if content and content.platform else None),
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
        reason_code=item.last_error_type,
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
    rule_id: Optional[int] = Query(None, description="按规则ID过滤"),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取队列统计信息。"""
    conditions = []
    if rule_id is not None:
        conditions.append(ContentQueueItem.rule_id == rule_id)

    where_clause = and_(*conditions) if conditions else True

    rows_result = await db.execute(
        select(
            ContentQueueItem.content_id,
            ContentQueueItem.status,
            ContentQueueItem.needs_approval,
            ContentQueueItem.approved_at,
        ).where(where_clause)
    )

    grouped: dict[int, dict[str, bool]] = {}
    for content_id, status, needs_approval, approved_at in rows_result.all():
        flags = grouped.setdefault(
            int(content_id),
            {
                "pending_review": False,
                "will_push": False,
                "pushed": False,
                "filtered": False,
            },
        )

        if status == QueueItemStatus.PENDING and bool(needs_approval) and approved_at is None:
            flags["pending_review"] = True
        elif status in (
            QueueItemStatus.PENDING,
            QueueItemStatus.SCHEDULED,
            QueueItemStatus.PROCESSING,
            QueueItemStatus.FAILED,
        ):
            flags["will_push"] = True
        elif status == QueueItemStatus.SUCCESS:
            flags["pushed"] = True
        elif status in (QueueItemStatus.SKIPPED, QueueItemStatus.CANCELED):
            flags["filtered"] = True

    stats = {
        "will_push": 0,
        "filtered": 0,
        "pending_review": 0,
        "pushed": 0,
        "total": len(grouped),
    }

    for flags in grouped.values():
        if flags["pending_review"]:
            stats["pending_review"] += 1
        elif flags["will_push"]:
            stats["will_push"] += 1
        elif flags["pushed"]:
            stats["pushed"] += 1
        elif flags["filtered"]:
            stats["filtered"] += 1

    now = utcnow()
    due_result = await db.execute(
        select(func.count(func.distinct(ContentQueueItem.content_id))).where(
            and_(
                where_clause,
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

    from app.services.distribution import enqueue_content

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
    item.last_error = None
    item.last_error_type = None
    item.last_error_at = None
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
    item.last_error = "Canceled manually"
    item.last_error_type = "manual_canceled"
    item.last_error_at = utcnow()

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
        item.last_error = None
        item.last_error_type = None
        item.last_error_at = None
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
        rules_map: dict[int, DistributionRule] = {}

        async def _get_rule(rule_id: int) -> Optional[DistributionRule]:
            if rule_id in rules_map:
                return rules_map[rule_id]
            rule_result = await db.execute(
                select(DistributionRule).where(DistributionRule.id == rule_id)
            )
            rule = rule_result.scalar_one_or_none()
            if rule:
                rules_map[rule_id] = rule
            return rule

        changed = 0
        for item in items:
            if item.status in (QueueItemStatus.SUCCESS, QueueItemStatus.CANCELED):
                continue

            rule = await _get_rule(item.rule_id)
            if rule:
                scheduled_at = await compute_auto_scheduled_at(
                    session=db,
                    rule=rule,
                    bot_chat_id=item.bot_chat_id,
                    target_id=item.target_id,
                )
            else:
                scheduled_at = now

            item.status = QueueItemStatus.SCHEDULED
            item.needs_approval = False
            item.scheduled_at = scheduled_at
            item.next_attempt_at = None
            item.last_error = None
            item.last_error_type = None
            item.last_error_at = None
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
        reason = str(payload.get("reason") or "Filtered manually").strip() or "Filtered manually"
        for item in items:
            if item.status == QueueItemStatus.SUCCESS:
                continue
            item.status = QueueItemStatus.CANCELED
            item.locked_at = None
            item.locked_by = None
            item.last_error = reason
            item.last_error_type = "manual_filtered"
            item.last_error_at = now
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


@router.post("/content/{content_id}/repush-now")
async def repush_now_content_queue(
    content_id: int,
    target_id: Optional[str] = Query(None, description="仅重推指定目标ID"),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """手动重推：删除去重记录并立即重新排期。"""
    now = utcnow()

    result = await db.execute(
        select(ContentQueueItem).where(ContentQueueItem.content_id == content_id)
    )
    items = result.scalars().all()

    changed = 0
    affected_targets: set[str] = set()
    for item in items:
        if target_id and item.target_id != target_id:
            continue
        item.status = QueueItemStatus.SCHEDULED
        item.needs_approval = False
        item.scheduled_at = now
        item.next_attempt_at = None
        item.locked_at = None
        item.locked_by = None
        item.message_id = None
        item.last_error = None
        item.last_error_type = None
        item.last_error_at = None
        changed += 1
        affected_targets.add(item.target_id)

    deleted_records = 0
    if affected_targets:
        delete_stmt = PushedRecord.__table__.delete().where(
            and_(
                PushedRecord.content_id == content_id,
                PushedRecord.target_id.in_(list(affected_targets)),
            )
        )
        delete_result = await db.execute(delete_stmt)
        deleted_records = int(delete_result.rowcount or 0)

    await db.commit()
    await event_bus.publish("queue_updated", {
        "action": "content_repush_now",
        "content_id": content_id,
        "target_id": target_id,
        "items_changed": changed,
        "deleted_records": deleted_records,
        "timestamp": now.isoformat(),
    })
    return {
        "status": "ok",
        "changed": changed,
        "deleted_records": deleted_records,
    }


@router.post("/content/batch-repush-now")
async def batch_repush_now_content_queue(
    payload: dict = Body(default={}),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """批量手动重推：删除去重记录并立即重新排期。"""
    content_ids = [int(cid) for cid in (payload.get("content_ids") or [])]
    if not content_ids:
        return {"status": "ok", "changed": 0, "deleted_records": 0}

    now = utcnow()
    result = await db.execute(
        select(ContentQueueItem).where(ContentQueueItem.content_id.in_(content_ids))
    )
    items = result.scalars().all()

    changed = 0
    target_pairs: set[tuple[int, str]] = set()
    for item in items:
        item.status = QueueItemStatus.SCHEDULED
        item.needs_approval = False
        item.scheduled_at = now
        item.next_attempt_at = None
        item.locked_at = None
        item.locked_by = None
        item.message_id = None
        item.last_error = None
        item.last_error_type = None
        item.last_error_at = None
        changed += 1
        target_pairs.add((item.content_id, item.target_id))

    deleted_records = 0
    for cid, tid in target_pairs:
        delete_result = await db.execute(
            PushedRecord.__table__.delete().where(
                and_(
                    PushedRecord.content_id == cid,
                    PushedRecord.target_id == tid,
                )
            )
        )
        deleted_records += int(delete_result.rowcount or 0)

    await db.commit()
    await event_bus.publish("queue_updated", {
        "action": "content_batch_repush_now",
        "content_ids": content_ids,
        "items_changed": changed,
        "deleted_records": deleted_records,
        "timestamp": now.isoformat(),
    })
    return {
        "status": "ok",
        "changed": changed,
        "deleted_records": deleted_records,
    }


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
            item.last_error = None
            item.last_error_type = None
            item.last_error_at = None
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
            item.last_error = None
            item.last_error_type = None
            item.last_error_at = None
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
            item.last_error = None
            item.last_error_type = None
            item.last_error_at = None
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
                item.last_error = None
                item.last_error_type = None
                item.last_error_at = None
                changed += 1

    await db.commit()
    await event_bus.publish("queue_updated", {
        "action": "content_batch_reschedule",
        "content_ids": content_ids,
        "items_changed": changed,
        "timestamp": utcnow().isoformat(),
    })
    return {"status": "ok", "changed": changed}
