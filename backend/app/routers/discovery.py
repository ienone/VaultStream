"""
Discovery API — 发现缓冲区管理
"""
from typing import Optional, List
import time
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import select, func, desc, asc, cast, String, or_, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.events import event_bus
from app.core.dependencies import require_api_token
from app.core.api_errors import build_error_payload
from app.core.time_utils import utcnow
from app.services.background_task_state import (
    record_task_run_error,
    record_task_run_started,
    record_task_run_success,
)
from app.services.config_service import ConfigService
from app.models import Content, DiscoverySource, DiscoveryState, DiscoverySourceKind
from app.schemas.discovery import (
    DiscoveryItemListItem, DiscoveryItemListResponse, DiscoveryItemResponse,
    DiscoveryItemUpdate, DiscoveryBulkAction,
    DiscoverySourceCreate, DiscoverySourceUpdate, DiscoverySourceResponse,
    DiscoverySettingsResponse, DiscoverySettingsUpdate,
    DiscoveryStatsResponse,
)

router = APIRouter()


_ALLOWED_SORT_FIELDS = {
    "created_at": Content.created_at,
    "updated_at": Content.updated_at,
    "discovered_at": Content.discovered_at,
    "published_at": Content.published_at,
    "ai_score": Content.ai_score,
}
_SUPPORTED_DISCOVERY_SOURCE_KINDS = {
    DiscoverySourceKind.RSS,
    DiscoverySourceKind.TELEGRAM_CHANNEL,
}
_SUPPORTED_DISCOVERY_SOURCE_KIND_VALUES = [k.value for k in _SUPPORTED_DISCOVERY_SOURCE_KINDS]
_SOURCE_TEST_SAMPLE_LIMIT = 5


def _source_kind_value(kind: DiscoverySourceKind | str) -> str:
    return kind.value if hasattr(kind, "value") else str(kind)


def _raise_unsupported_source_kind(kind: DiscoverySourceKind | str, request: Request | None = None) -> None:
    kind_value = _source_kind_value(kind)
    raise HTTPException(
        status_code=400,
        detail=build_error_payload(
            message=f"Discovery source kind is not supported yet: {kind_value}",
            code="source_kind_not_supported",
            hint="当前发现源仅支持 RSS 和 Telegram Channel，其他来源仍在路线图中。",
            request_id=getattr(getattr(request, "state", None), "request_id", None),
            extra={"supported_kinds": sorted(_SUPPORTED_DISCOVERY_SOURCE_KIND_VALUES)},
        ),
    )


async def _read_discovery_settings(config: ConfigService) -> DiscoverySettingsResponse:
    interest_profile = await config.get_value("discovery_interest_profile", "")
    score_threshold = await config.get_value("discovery_score_threshold", 6.0)
    retention_days = await config.get_value("discovery_retention_days", 7)

    return DiscoverySettingsResponse(
        interest_profile=str(interest_profile or ""),
        score_threshold=float(score_threshold) if score_threshold is not None else 6.0,
        retention_days=int(retention_days) if retention_days is not None else 7,
    )


def _parse_list_param(values: Optional[List[str]]) -> Optional[List[str]]:
    """支持逗号分隔和重复 query key 的 List 参数。"""
    if not values:
        return None
    result: list[str] = []
    for value in values:
        if not value:
            continue
        if "," in value:
            result.extend([v.strip() for v in value.split(",") if v.strip()])
        else:
            result.append(value.strip())
    return result or None


def _serialize_source_test_item(item) -> dict:
    return {
        "url": item.url,
        "title": item.title,
        "author": item.author,
        "published_at": item.published_at.isoformat() if item.published_at else None,
        "tag_count": len(item.source_tags or []),
        "media_count": len(item.media_urls or []),
    }


# ── Items ──────────────────────────────────────────────────────────────

@router.get("/discovery/items", response_model=DiscoveryItemListResponse)
async def list_discovery_items(
    page: int = Query(1, ge=1),
    size: int = Query(20, ge=1, le=100),
    sort: str = Query("created_at"),
    order: str = Query("desc"),
    state: Optional[DiscoveryState] = Query(None),
    show_all: bool = Query(False),
    source_kind: Optional[str] = Query(None),
    source_name: Optional[str] = Query(None),
    score_min: Optional[float] = Query(None),
    score_max: Optional[float] = Query(None),
    tags: Optional[List[str]] = Query(None, alias="tag"),
    q: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    query = select(Content).where(Content.discovery_state.isnot(None))

    if state:
        query = query.where(Content.discovery_state == state)
    elif not show_all:
        # 默认只显示未处理或评分过的可见内容，忽略和已收藏的（默认）移出视图
        query = query.where(Content.discovery_state.in_([
            DiscoveryState.INGESTED,
            DiscoveryState.SCORED,
            DiscoveryState.VISIBLE
        ]))

    if source_kind or source_name:
        query = query.join(
            DiscoverySource,
            Content.discovery_source_id == DiscoverySource.id,
        )
        if source_kind:
            query = query.where(DiscoverySource.kind == source_kind)
        if source_name:
            query = query.where(DiscoverySource.name == source_name)
    if score_min is not None:
        query = query.where(Content.ai_score >= score_min)
    if score_max is not None:
        query = query.where(Content.ai_score <= score_max)
    if q:
        query = query.where(Content.title.ilike(f"%{q}%"))
    normalized_tags = _parse_list_param(tags)
    if normalized_tags:
        tag_conditions = []
        for tag in normalized_tags:
            normalized_tag = (tag or "").strip()
            if not normalized_tag:
                continue

            escaped_tag = (
                normalized_tag
                .replace("\\", "\\\\")
                .replace("%", "\\%")
                .replace("_", "\\_")
                .replace('"', '\\"')
            )
            # JSON arrays are stored as serialized text in SQLite; use quoted token matching.
            pattern = f'%"{escaped_tag}"%'
            tag_conditions.extend([
                cast(Content.ai_tags, String).ilike(pattern, escape="\\"),
                cast(Content.tags, String).ilike(pattern, escape="\\"),
            ])

        if tag_conditions:
            query = query.where(or_(*tag_conditions))

    # count
    count_q = select(func.count()).select_from(query.subquery())
    total = (await db.execute(count_q)).scalar() or 0

    # sort
    sort_col = _ALLOWED_SORT_FIELDS.get(sort, Content.created_at)
    query = query.order_by(desc(sort_col) if order.lower() == "desc" else asc(sort_col))

    # paginate
    query = query.offset((page - 1) * size).limit(size)
    result = await db.execute(query)
    items = result.scalars().all()

    return {
        "items": [DiscoveryItemListItem.model_validate(i) for i in items],
        "total": total,
        "page": page,
        "size": size,
        "has_more": total > page * size,
    }


@router.get("/discovery/items/{item_id}", response_model=DiscoveryItemResponse)
async def get_discovery_item(
    item_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    result = await db.execute(
        select(Content).where(
            Content.id == item_id,
            Content.discovery_state.isnot(None),
        )
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Discovery item not found")
    return DiscoveryItemResponse.model_validate(item)


@router.patch("/discovery/items/{item_id}", response_model=DiscoveryItemResponse)
async def update_discovery_item(
    item_id: int,
    body: DiscoveryItemUpdate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    result = await db.execute(
        select(Content).where(
            Content.id == item_id,
            Content.discovery_state.isnot(None),
        )
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Discovery item not found")

    if body.state == "promoted":
        item.discovery_state = DiscoveryState.PROMOTED
        item.promoted_at = utcnow()
    else:
        item.discovery_state = DiscoveryState.IGNORED

    await db.commit()
    await db.refresh(item)
    await event_bus.publish("content_updated", {
        "id": item.id,
        "title": item.title,
        "platform": item.platform.value if item.platform else None,
        "discovery_state": item.discovery_state.value if item.discovery_state else None,
    })
    return DiscoveryItemResponse.model_validate(item)


@router.post("/discovery/items/bulk-action")
async def bulk_action(
    body: DiscoveryBulkAction,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    if not body.ids:
        return {"updated": 0}

    result = await db.execute(
        select(Content).where(
            Content.id.in_(body.ids),
            Content.discovery_state.isnot(None),
        )
    )
    items = result.scalars().all()

    now = utcnow()
    for item in items:
        if body.action == "promote":
            item.discovery_state = DiscoveryState.PROMOTED
            item.promoted_at = now
        else:
            item.discovery_state = DiscoveryState.IGNORED

    await db.commit()
    for item in items:
        await event_bus.publish("content_updated", {
            "id": item.id,
            "title": item.title,
            "platform": item.platform.value if item.platform else None,
            "discovery_state": item.discovery_state.value if item.discovery_state else None,
        })
    return {"updated": len(items)}


# ── Sources ────────────────────────────────────────────────────────────

@router.get("/discovery/sources", response_model=List[DiscoverySourceResponse])
async def list_sources(
    kind: Optional[DiscoverySourceKind] = Query(None),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    if kind and kind not in _SUPPORTED_DISCOVERY_SOURCE_KINDS:
        _raise_unsupported_source_kind(kind)

    query = select(DiscoverySource).where(
        DiscoverySource.kind.in_(_SUPPORTED_DISCOVERY_SOURCE_KIND_VALUES)
    )
    if kind:
        query = query.where(DiscoverySource.kind == kind)
    result = await db.execute(query)
    return [DiscoverySourceResponse.model_validate(s) for s in result.scalars().all()]


@router.post("/discovery/sources", response_model=DiscoverySourceResponse, status_code=201)
async def create_source(
    body: DiscoverySourceCreate,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    if body.kind not in _SUPPORTED_DISCOVERY_SOURCE_KINDS:
        _raise_unsupported_source_kind(body.kind, request)

    source = DiscoverySource(
        kind=body.kind,
        name=body.name,
        enabled=body.enabled,
        config=body.config,
        sync_interval_minutes=body.sync_interval_minutes,
    )
    db.add(source)
    await db.commit()
    await db.refresh(source)
    return DiscoverySourceResponse.model_validate(source)


@router.get("/discovery/sources/{source_id}", response_model=DiscoverySourceResponse)
async def get_source(
    source_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    result = await db.execute(
        select(DiscoverySource).where(
            DiscoverySource.id == source_id,
            DiscoverySource.kind.in_(_SUPPORTED_DISCOVERY_SOURCE_KIND_VALUES),
        )
    )
    source = result.scalar_one_or_none()
    if not source:
        raise HTTPException(status_code=404, detail="Source not found")
    return DiscoverySourceResponse.model_validate(source)


@router.put("/discovery/sources/{source_id}", response_model=DiscoverySourceResponse)
async def update_source(
    source_id: int,
    body: DiscoverySourceUpdate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    result = await db.execute(
        select(DiscoverySource).where(
            DiscoverySource.id == source_id,
            DiscoverySource.kind.in_(_SUPPORTED_DISCOVERY_SOURCE_KIND_VALUES),
        )
    )
    source = result.scalar_one_or_none()
    if not source:
        raise HTTPException(status_code=404, detail="Source not found")

    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(source, field, value)

    await db.commit()
    await db.refresh(source)
    return DiscoverySourceResponse.model_validate(source)


@router.delete("/discovery/sources/{source_id}")
async def delete_source(
    source_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    result = await db.execute(
        select(DiscoverySource).where(
            DiscoverySource.id == source_id,
            DiscoverySource.kind.in_(_SUPPORTED_DISCOVERY_SOURCE_KIND_VALUES),
        )
    )
    source = result.scalar_one_or_none()
    if not source:
        raise HTTPException(status_code=404, detail="Source not found")

    await db.delete(source)
    await db.commit()
    return {"success": True, "id": source_id}


@router.post("/discovery/sources/{source_id}/test")
async def test_source_quality(
    source_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    result = await db.execute(
        select(DiscoverySource).where(DiscoverySource.id == source_id)
    )
    source = result.scalar_one_or_none()
    if not source:
        raise HTTPException(status_code=404, detail="Source not found")
    if source.kind not in _SUPPORTED_DISCOVERY_SOURCE_KINDS:
        _raise_unsupported_source_kind(source.kind, request)

    from app.tasks.discovery_sync import DiscoverySyncTask

    run = await record_task_run_started(
        "discovery_source_test",
        trigger="manual",
        source_id=source.id,
        source_name=source.name,
        source_kind=_source_kind_value(source.kind),
    )
    started = time.perf_counter()
    try:
        scraper = DiscoverySyncTask()._get_scraper(source)
        if scraper is None:
            raise RuntimeError(f"Unsupported discovery source kind: {_source_kind_value(source.kind)}")

        items, new_cursor = await scraper.fetch(last_cursor=None)
        elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
        samples = [
            _serialize_source_test_item(item)
            for item in items[:_SOURCE_TEST_SAMPLE_LIMIT]
        ]
        payload = {
            "source_id": source.id,
            "source_name": source.name,
            "source_kind": _source_kind_value(source.kind),
            "item_count": len(items),
            "sample_count": len(samples),
            "samples": samples,
            "cursor_available": bool(new_cursor),
            "elapsed_ms": elapsed_ms,
        }
        await record_task_run_success(
            "discovery_source_test",
            run["run_id"],
            **payload,
        )
        status = "ok" if items else "empty"
        return {
            "run_id": run["run_id"],
            "ok": bool(items),
            "status": status,
            **payload,
        }
    except Exception as exc:
        elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
        await record_task_run_error(
            "discovery_source_test",
            run["run_id"],
            exc,
            trigger="manual",
            source_id=source.id,
            source_name=source.name,
            source_kind=_source_kind_value(source.kind),
            elapsed_ms=elapsed_ms,
        )
        return {
            "run_id": run["run_id"],
            "ok": False,
            "status": "error",
            "source_id": source.id,
            "source_name": source.name,
            "source_kind": _source_kind_value(source.kind),
            "error": str(exc)[:1000],
            "elapsed_ms": elapsed_ms,
        }


@router.post("/discovery/sources/{source_id}/sync", status_code=202)
async def trigger_sync(
    source_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    result = await db.execute(
        select(DiscoverySource).where(DiscoverySource.id == source_id)
    )
    source = result.scalar_one_or_none()
    if not source:
        raise HTTPException(status_code=404, detail="Source not found")
    if source.kind not in _SUPPORTED_DISCOVERY_SOURCE_KINDS:
        _raise_unsupported_source_kind(source.kind, request)

    sync_task = getattr(request.app.state, "discovery_sync_task", None)
    if sync_task is None:
        raise HTTPException(
            status_code=503,
            detail=build_error_payload(
                message="Discovery sync task is not running",
                code="discovery_task_unavailable",
                hint="请确认后端发现同步任务已启动后重试",
                request_id=getattr(request.state, "request_id", None),
            ),
        )

    run = await sync_task.create_run(source, trigger="manual")
    import asyncio
    asyncio.create_task(
        sync_task.sync_source_by_id(
            source_id,
            run_id=run["run_id"],
            trigger="manual",
        )
    )

    return {"status": "accepted", "source_id": source_id, "run_id": run["run_id"]}


# ── Settings ───────────────────────────────────────────────────────────

@router.get("/discovery/settings", response_model=DiscoverySettingsResponse)
async def get_discovery_settings(
    _: None = Depends(require_api_token),
):
    return await _read_discovery_settings(ConfigService())


@router.patch("/discovery/settings", response_model=DiscoverySettingsResponse)
async def update_discovery_settings(
    body: DiscoverySettingsUpdate,
    _: None = Depends(require_api_token),
):
    config = ConfigService()

    if body.interest_profile is not None:
        await config.set_value("discovery_interest_profile", body.interest_profile, category="discovery")
    if body.score_threshold is not None:
        await config.set_value("discovery_score_threshold", body.score_threshold, category="discovery")
    if body.retention_days is not None:
        await config.set_value("discovery_retention_days", body.retention_days, category="discovery")

    return await _read_discovery_settings(config)


# ── Stats ──────────────────────────────────────────────────────────────

@router.get("/discovery/stats", response_model=DiscoveryStatsResponse)
async def get_discovery_stats(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    # total
    total_q = select(func.count()).select_from(Content).where(Content.discovery_state.isnot(None))
    total = (await db.execute(total_q)).scalar() or 0

    # by state
    state_q = (
        select(Content.discovery_state, func.count())
        .where(Content.discovery_state.isnot(None))
        .group_by(Content.discovery_state)
    )
    state_rows = (await db.execute(state_q)).all()
    by_state = {
        row[0].value: row[1]
        for row in state_rows
        if row[0] is not None
    }

    # by source
    source_q = (
        select(Content.source_type, func.count())
        .where(Content.discovery_state.isnot(None))
        .group_by(Content.source_type)
    )
    source_rows = (await db.execute(source_q)).all()
    by_source = {
        str(row[0] or "unknown"): row[1]
        for row in source_rows
    }

    return DiscoveryStatsResponse(total=total, by_state=by_state, by_source=by_source)
