"""
分发队列管理 API（ContentQueueItem 架构）
"""
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request
from sqlalchemy import and_, case, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import load_only

from app.core.database import get_db
from app.core.dependencies import require_api_token
from app.core.events import event_bus
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.models import Content, ContentQueueItem, QueueItemStatus, PushedRecord
from app.schemas import (
    BatchQueueRetryResponse,
    BatchQueueRetryRequest,
    ContentQueueItemListResponse,
    ContentQueueItemResponse,
    EnqueueContentRequest,
    QueueChangedResponse,
    QueueEnqueueResponse,
    QueueStatsResponse,
)
from app.schemas.media import MediaAssetManifest, MediaPurpose
from app.schemas.queue import (
    ManualPushRequest, ManualPushResponse, BatchQueueCancelRequest, BatchQueueCancelResponse,
    BatchQueueSendResponse, BatchScheduleRequest, QueueSelection, QueueSendResult,
)
from app.services.distribution.delivery_state import delivery_bucket, visible_queue_item
from app.services.distribution.queue_operations import (
    QueueEditConflict, cancel_items, lock_item_for_edit, schedule_item,
)
from app.services.background_task_state import (
    record_task_run_error,
    record_task_run_started,
    record_task_run_success,
)
from app.services.media_manifest import (
    build_content_media_manifests,
    resolve_media_base_url,
)
from app.tasks import DistributionQueueWorker
from app.utils.datetime_utils import normalize_datetime_for_db


router = APIRouter(prefix="/distribution-queue", tags=["distribution-queue"])


async def _lock_queue_item_for_edit(db: AsyncSession, item: ContentQueueItem) -> None:
    try:
        await lock_item_for_edit(db, item)
    except QueueEditConflict as exc:
        raise HTTPException(status_code=409, detail={
            "code": "queue_item_requires_review", "message": str(exc),
        }) from exc


def _as_utc(dt: Optional[datetime]) -> Optional[datetime]:
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _to_queue_item_response(
    item: ContentQueueItem,
    content: Optional[Content] = None,
    *,
    media_assets: list[MediaAssetManifest] | None = None,
) -> ContentQueueItemResponse:
    return ContentQueueItemResponse(
        id=item.id,
        content_id=item.content_id,
        title=(content.title if content else None),
        tags=((content.tags or []) if content else []),
        is_nsfw=bool(content.is_nsfw) if content else False,
        cover_url=(content.cover_url if content else None),
        author_name=(content.author_name if content else None),
        media_assets=media_assets or [],
        rule_id=item.rule_id,
        bot_chat_id=item.bot_chat_id,
        source_platform=(content.platform.value if content and content.platform else None),
        target_platform=item.target_platform,
        target_id=item.target_id,
        status=item.status.value,
        priority=item.priority or 0,
        scheduled_at=_as_utc(item.scheduled_at),
        approved_by=item.approved_by,
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


async def _queue_media_assets(
    db: AsyncSession,
    content_ids: list[int],
    request: Request,
) -> dict[int, list[MediaAssetManifest]]:
    return await build_content_media_manifests(
        db,
        content_ids,
        purpose=MediaPurpose.CARD,
        base_url=resolve_media_base_url(str(request.base_url)),
    )


async def _queue_item_response_with_media(
    db: AsyncSession,
    item: ContentQueueItem,
    content: Optional[Content],
    request: Request,
) -> ContentQueueItemResponse:
    manifests = await _queue_media_assets(db, [item.content_id], request)
    return _to_queue_item_response(
        item,
        content,
        media_assets=manifests.get(item.content_id, []),
    )


def _build_status_conditions(status: Optional[str]):
    if not status:
        return []
    if status == "history":
        return [delivery_bucket().in_(["pushed", "filtered"])]
    if status in {"will_push", "filtered", "pushed"}:
        return [delivery_bucket() == status]
    try:
        return [ContentQueueItem.status == QueueItemStatus(status)]
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Invalid status: {status}")


@router.post("/manual", response_model=ManualPushResponse)
async def prepare_manual_delivery(
    payload: ManualPushRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """Prepare explicit target deliveries; push-now executes each returned item."""
    from app.services.distribution.manual import prepare_manual_push
    return await prepare_manual_push(db, payload)


@router.get("/stats", response_model=QueueStatsResponse)
async def get_queue_stats(
    rule_id: Optional[int] = Query(None, description="按规则ID过滤"),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取队列统计信息。"""
    conditions = [visible_queue_item()]
    if rule_id is not None:
        conditions.append(ContentQueueItem.rule_id == rule_id)

    where_clause = and_(*conditions)

    result = await db.execute(select(
        func.count().label("total"),
        func.count(case((and_(*_build_status_conditions("will_push")), 1))).label("will_push"),
        func.count(case((and_(*_build_status_conditions("filtered")), 1))).label("filtered"),
        func.count(case((ContentQueueItem.status == QueueItemStatus.SUCCESS, 1))).label("pushed"),
        func.count(case((and_(
            ContentQueueItem.status == QueueItemStatus.SCHEDULED,
            ContentQueueItem.scheduled_at <= utcnow(),
        ), 1))).label("due_now"),
    ).select_from(ContentQueueItem).where(where_clause))
    return QueueStatsResponse(**result.mappings().one())


@router.get("/items", response_model=ContentQueueItemListResponse)
async def list_queue_items(
    request: Request,
    status: Optional[str] = Query(None, description="状态过滤（支持别名 will_push/filtered/pushed）"),
    content_id: Optional[int] = Query(None, description="按内容ID过滤"),
    rule_id: Optional[int] = Query(None, description="按规则ID过滤"),
    bot_chat_id: Optional[int] = Query(None, description="按BotChat ID过滤"),
    page: int = Query(1, ge=1, description="页码"),
    size: int = Query(50, ge=1, le=200, description="每页数量"),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取队列项列表（分页）。"""
    conditions = [visible_queue_item()]

    conditions.extend(_build_status_conditions(status))

    if content_id is not None:
        conditions.append(ContentQueueItem.content_id == content_id)
    if rule_id is not None:
        conditions.append(ContentQueueItem.rule_id == rule_id)
    if bot_chat_id is not None:
        conditions.append(ContentQueueItem.bot_chat_id == bot_chat_id)

    where_clause = and_(*conditions)

    count_result = await db.execute(
        select(func.count(ContentQueueItem.id)).where(where_clause)
    )
    total = int(count_result.scalar() or 0)

    offset = (page - 1) * size
    ordering = (
        (ContentQueueItem.updated_at.desc(), ContentQueueItem.id.desc())
        if status in {"pushed", "filtered", "history", QueueItemStatus.SUCCESS.value}
        else (ContentQueueItem.scheduled_at.asc(), ContentQueueItem.id.asc())
    )
    result = await db.execute(
        select(ContentQueueItem, Content)
        .options(load_only(Content.id, Content.title, Content.tags, Content.is_nsfw,
                           Content.cover_url, Content.author_name, Content.platform))
        .join(Content, Content.id == ContentQueueItem.content_id, isouter=True)
        .where(where_clause)
        .order_by(*ordering)
        .offset(offset)
        .limit(size)
    )
    rows = result.all()
    media_assets = await _queue_media_assets(
        db,
        list({item.content_id for item, _content in rows}),
        request,
    )

    return ContentQueueItemListResponse(
        items=[
            _to_queue_item_response(
                item,
                content,
                media_assets=media_assets.get(item.content_id, []),
            )
            for item, content in rows
        ],
        total=total,
        page=page,
        size=size,
        has_more=(offset + size) < total,
    )


@router.get("/items/{item_id}", response_model=ContentQueueItemResponse)
async def get_queue_item(
    item_id: int,
    request: Request,
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
    return await _queue_item_response_with_media(db, item, content, request)


@router.post("/items/{item_id}/push-now", response_model=ContentQueueItemResponse)
async def push_queue_item_now(
    item_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    result, run_id = await _send_queue_item(item_id, db, request.app.state.distribution_worker)
    if not result.sent and run_id is None:
        raise HTTPException(409, result.error)
    item, content = (await db.execute(select(ContentQueueItem, Content).outerjoin(
        Content, Content.id == ContentQueueItem.content_id,
    ).where(ContentQueueItem.id == item_id).execution_options(populate_existing=True))).one()
    response = await _queue_item_response_with_media(db, item, content, request)
    response.run_id = run_id
    return response


async def _send_queue_item(item_id: int, db: AsyncSession, worker: DistributionQueueWorker) -> tuple[QueueSendResult, str | None]:
    item = await db.get(ContentQueueItem, item_id, populate_existing=True)
    if item is None:
        return QueueSendResult(item_id=item_id, sent=False, error="队列项不存在"), None
    details = dict(queue_item_id=item_id, content_id=item.content_id,
                   target_platform=item.target_platform, target_id=item.target_id, trigger="manual")
    await db.commit()
    run = await record_task_run_started("distribution_push", **details)
    try:
        await worker.process_item_now(item_id)
    except ValueError as error:
        await record_task_run_error("distribution_push", run["run_id"], error, **details)
        return QueueSendResult(item_id=item_id, sent=False, error=str(error)), None
    except Exception as error:
        await record_task_run_error("distribution_push", run["run_id"], error, **details)
        raise
    await db.refresh(item)
    sent = item.status == QueueItemStatus.SUCCESS
    reason = None if sent else (item.last_error or "尚未发送")
    details.update(status=item.status.value, last_error_type=item.last_error_type,
                   attempt_count=item.attempt_count)
    await db.commit()
    if sent:
        await record_task_run_success("distribution_push", run["run_id"], message_id=item.message_id, **details)
    else:
        await record_task_run_error("distribution_push", run["run_id"], reason, **details)
    return QueueSendResult(item_id=item_id, sent=sent, error=reason), run["run_id"]


@router.post("/enqueue/{content_id}", response_model=QueueEnqueueResponse)
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

    from app.services.distribution import DistributionService

    enqueued_count = await DistributionService(db).enqueue_content(
        content_id,
        force=request.force,
        manual=True,
    )
    logger.info(f"手动入队: content_id={content_id}, enqueued={enqueued_count}")
    return {"status": "ok", "enqueued_count": enqueued_count}


@router.post("/cancel", response_model=BatchQueueCancelResponse)
async def cancel_queue_items(
    payload: BatchQueueCancelRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """Cancel the selected queue items in one transaction and publish once."""
    now = utcnow()
    try:
        ids = await cancel_items(db, payload.item_ids, at=now)
    except QueueEditConflict as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    await event_bus.publish("queue_updated", {
        "action": "cancel_items", "queue_item_ids": ids, "timestamp": now.isoformat(),
    })
    return {"canceled_ids": ids}


@router.post("/batch-retry", response_model=BatchQueueRetryResponse)
async def batch_retry_queue_items(
    request: BatchQueueRetryRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """批量重试队列项。"""
    conditions = [ContentQueueItem.status == QueueItemStatus.FAILED]
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
        await _lock_queue_item_for_edit(db, item)
        schedule_item(item, at=now)
        retried_ids.append(item.id)

    await db.commit()

    await event_bus.publish("queue_updated", {
        "action": "batch_retry",
        "retried_count": len(retried_ids),
        "queue_item_ids": retried_ids,
        "timestamp": utcnow().isoformat(),
    })
    return {"retried_count": len(retried_ids), "item_ids": retried_ids}


@router.post("/items/batch-push-now", response_model=BatchQueueSendResponse)
async def batch_push_now_queue_items(
    payload: QueueSelection,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    results = []
    for item_id in dict.fromkeys(payload.item_ids):
        result, _run_id = await _send_queue_item(item_id, db, request.app.state.distribution_worker)
        results.append(result)
    return BatchQueueSendResponse(items=results)


@router.post("/items/batch-schedule", response_model=QueueChangedResponse, response_model_exclude_none=True)
async def batch_schedule_queue_items(
    payload: BatchScheduleRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    ids = list(dict.fromkeys(payload.item_ids))
    items = {item.id: item for item in await db.scalars(
        select(ContentQueueItem).where(ContentQueueItem.id.in_(ids))
    )}
    if len(items) != len(ids) or any(
        item.status not in (QueueItemStatus.SCHEDULED, QueueItemStatus.FAILED) for item in items.values()
    ):
        raise HTTPException(409, "所选记录已变化，请刷新后重试")
    start = normalize_datetime_for_db(payload.start_time)
    for index, item_id in enumerate(ids):
        item = items[item_id]
        await _lock_queue_item_for_edit(db, item)
        schedule_item(item, at=start + timedelta(seconds=index * payload.interval_seconds))
    await db.commit()
    await event_bus.publish("queue_updated", {"action": "item_batch_schedule", "queue_item_ids": ids})
    return {"status": "ok", "changed": len(ids)}
