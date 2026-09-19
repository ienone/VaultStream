"""
语义检索 API
"""
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm.exc import StaleDataError

from app.core.database import AsyncSessionLocal
from app.core.database import get_db
from app.core.dependencies import require_api_token
from app.models import ContentStatus, Platform
from app.schemas import (
    SemanticEmbeddingRetryResponse,
    SemanticIndexStatusResponse,
    SemanticReindexRequest,
    SemanticReindexResponse,
    UnifiedSearchContentItem,
    UnifiedSearchEventItem,
    UnifiedSearchFacetItem,
    UnifiedSearchResponse,
    UnifiedSearchTimepointItem,
)
from app.services.embedding_service import EmbeddingService
from app.services.search_service import UnifiedSearchService
from app.services.content_presenter import compute_effective_layout_type, transform_media_url
from app.schemas.media import MediaPurpose
from app.services.media_manifest import build_content_media_manifests, resolve_media_base_url
from app.services.background_task_state import (
    record_task_run_error,
    record_task_run_started,
    record_task_run_success,
)
from app.utils.datetime_utils import normalize_datetime_for_db

router = APIRouter()


def _serialize_content_hit(hit, media_assets, base_url) -> UnifiedSearchContentItem:
    return UnifiedSearchContentItem(
        content_id=hit.content.id,
        score=float(hit.score),
        match_source=hit.match_source,
        chunk_title=hit.chunk_title,
        source_text=hit.source_text,
        platform=hit.content.platform.value if hit.content.platform else "",
        url=hit.content.url,
        status=hit.content.status.value if hit.content.status else "",
        review_status=hit.content.review_status.value if hit.content.review_status else None,
        discovery_state=hit.content.discovery_state.value if hit.content.discovery_state else None,
        content_type=hit.content.content_type,
        effective_layout_type=compute_effective_layout_type(hit.content),
        title=hit.content.title,
        summary=hit.content.summary,
        author_name=hit.content.author_name,
        author_avatar_url=transform_media_url(hit.content.author_avatar_url, base_url),
        cover_url=transform_media_url(hit.content.cover_url, base_url),
        cover_color=hit.content.cover_color,
        media_assets=media_assets,
        is_nsfw=hit.content.is_nsfw,
        view_count=hit.content.view_count or 0,
        like_count=hit.content.like_count or 0,
        tags=(hit.content.tags or []),
        created_at=hit.content.created_at,
        published_at=hit.content.published_at,
    )


@router.get("/search/unified", response_model=UnifiedSearchResponse)
async def unified_search(
    request: Request,
    q: str = Query("", description="检索词；空查询只允许 contents，返回筛选后的内容列表"),
    top_k: int = Query(20, ge=1, le=100, description="每类结果返回数量"),
    kind: Literal["all", "contents", "events", "people", "topics", "timepoints", "document_pages"] = Query(
        "all",
        description="结果类型：all/contents/events/people/topics/timepoints/document_pages",
    ),
    content_scope: Literal["library", "discovery", "all"] = Query(
        "library",
        description="内容范围：library/discovery/all；不影响事件结果",
    ),
    mode: Literal["keyword", "semantic"] = Query("semantic"),
    page: int = Query(1, ge=1, description="关键词内容分页；语义检索只支持第 1 页"),
    size: int = Query(20, ge=1, le=100),
    platforms: list[Platform] | None = Query(None, alias="platform"),
    statuses: list[ContentStatus] | None = Query(None, alias="status"),
    tags: list[str] | None = Query(None, alias="tag"),
    author: str | None = Query(None),
    date_from: datetime | None = Query(None),
    date_to: datetime | None = Query(None),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    if not q.strip() and kind != "contents":
        raise HTTPException(status_code=422, detail="空查询只支持内容浏览")
    if q.strip() and mode == "semantic" and page != 1:
        raise HTTPException(status_code=422, detail="语义检索使用 top_k，不支持分页")
    # SQLite 保存无时区 UTC；先归一化再比较，允许有/无偏移的 ISO 输入。
    date_from = normalize_datetime_for_db(date_from)
    date_to = normalize_datetime_for_db(date_to)
    if date_from is not None and date_to is not None and date_from > date_to:
        raise HTTPException(status_code=422, detail="开始日期不得晚于结束日期")

    results = await UnifiedSearchService(db).search(
        query=q.strip(),
        top_k=top_k,
        kind=kind,
        content_scope=content_scope,
        mode=mode, page=page, size=size,
        platforms=platforms, statuses=statuses, tags=tags,
        author=author.strip() if author else None,
        date_from=date_from, date_to=date_to,
    )
    base_url = resolve_media_base_url(str(request.base_url))
    manifests = await build_content_media_manifests(
        db, [hit.content.id for hit in results.contents], purpose=MediaPurpose.CARD,
        base_url=base_url,
    )
    events = []
    for hit in results.events:
        members = [member for member in hit.event.members if member.content is not None]
        members.sort(
            key=lambda member: (
                member.content.published_at
                or member.content.created_at
                or member.added_at
            )
        )
        events.append(
            UnifiedSearchEventItem(
                id=hit.event.id,
                title=hit.event.title,
                description=hit.event.description,
                status=hit.event.status.value,
                member_count=len(members),
                latest_member_title=members[-1].content.title if members else None,
                match_source=hit.match_source,
                created_at=hit.event.created_at,
                updated_at=hit.event.updated_at,
            )
        )
    return UnifiedSearchResponse(
        query=q.strip(),
        kind=kind,
        content_scope=content_scope,
        mode=mode, page=page, size=size,
        content_total=results.content_total,
        content_has_more=results.content_has_more,
        contents=[_serialize_content_hit(hit, manifests.get(hit.content.id, []), base_url) for hit in results.contents],
        document_pages=results.document_pages,
        events=events,
        people=[
            UnifiedSearchFacetItem(
                name=hit.name,
                content_count=hit.content_count,
                latest_content_id=hit.latest_content_id,
                latest_content_title=hit.latest_content_title,
            )
            for hit in results.people
        ],
        topics=[
            UnifiedSearchFacetItem(
                name=hit.name,
                content_count=hit.content_count,
                latest_content_id=hit.latest_content_id,
                latest_content_title=hit.latest_content_title,
            )
            for hit in results.topics
        ],
        timepoints=[
            UnifiedSearchTimepointItem(
                content_id=hit.content_id,
                content_title=hit.content_title,
                media_asset_id=hit.media_asset_id,
                media_type=hit.media_type,
                segment_type=hit.segment_type,
                title=hit.title,
                excerpt=hit.excerpt,
                start_seconds=hit.start_seconds,
                end_seconds=hit.end_seconds,
                match_source=hit.match_source,
                score=hit.score,
            )
            for hit in results.timepoints
        ],
    )


@router.get("/search/semantic/index-status", response_model=SemanticIndexStatusResponse)
async def semantic_index_status(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    status = await EmbeddingService().get_index_status(session=db)
    return SemanticIndexStatusResponse(**status)


async def _run_reindex_job(
    scope: str,
    content_id: int | None,
    limit: int,
    run_id: str,
) -> None:
    async with AsyncSessionLocal() as session:
        try:
            result = await EmbeddingService().reindex_scope(
                scope=scope,
                content_id=content_id,
                limit=limit,
                batch_size=8,
                delay_seconds=0.2,
                session=session,
            )
            await record_task_run_success("semantic_reindex", run_id, **result)
        except Exception as exc:
            await record_task_run_error(
                "semantic_reindex",
                run_id,
                exc,
                scope=scope,
                content_id=content_id,
                limit=limit,
            )
            raise


@router.post("/search/semantic/reindex", response_model=SemanticReindexResponse)
async def semantic_reindex(
    payload: SemanticReindexRequest,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    scope = payload.scope.strip().lower()
    if scope not in {"single", "all", "failed"}:
        raise HTTPException(status_code=400, detail="scope must be single, all or failed")
    if scope == "single" and payload.content_id is None:
        raise HTTPException(status_code=400, detail="content_id is required for single reindex")

    content_ids, estimated_calls = await EmbeddingService().plan_reindex(
        scope=scope,
        content_id=payload.content_id,
        limit=payload.limit,
        session=db,
    )
    run_id = None
    if not payload.dry_run:
        run = await record_task_run_started(
            "semantic_reindex",
            scope=scope,
            content_id=payload.content_id,
            limit=payload.limit,
            candidate_count=len(content_ids),
            estimated_embedding_calls=estimated_calls,
            trigger="manual",
        )
        run_id = run["run_id"]
        background_tasks.add_task(
            _run_reindex_job,
            scope,
            payload.content_id,
            payload.limit,
            run_id,
        )
    return SemanticReindexResponse(
        scope=scope,
        content_id=payload.content_id,
        dry_run=payload.dry_run,
        candidate_count=len(content_ids),
        estimated_embedding_calls=estimated_calls,
        scheduled=not payload.dry_run,
        run_id=run_id,
        message=(
            "dry run only; no paid embedding calls scheduled"
            if payload.dry_run
            else "reindex job scheduled with batch_size=8 and 0.2s inter-batch delay"
        ),
    )


@router.post(
    "/search/semantic/embeddings/{embedding_id}/retry",
    response_model=SemanticEmbeddingRetryResponse,
)
async def retry_semantic_embedding(
    embedding_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    run = await record_task_run_started(
        "semantic_reindex",
        trigger="manual",
        scope="embedding",
        embedding_id=embedding_id,
        candidate_count=1,
    )
    try:
        result = await EmbeddingService().retry_embedding(embedding_id, session=db)
        if result["index_status"] == "failed":
            await db.commit()
            error = result.get("failure_reason") or "embedding retry failed"
            await record_task_run_error(
                "semantic_reindex",
                run["run_id"],
                error,
                trigger="manual",
                scope="embedding",
                embedding_id=embedding_id,
                content_id=result["content_id"],
                chunk_index=result["chunk_index"],
                failed=1,
            )
            raise HTTPException(status_code=503, detail=error)

        await db.commit()
        await record_task_run_success(
            "semantic_reindex",
            run["run_id"],
            trigger="manual",
            scope="embedding",
            embedding_id=embedding_id,
            content_id=result["content_id"],
            chunk_index=result["chunk_index"],
            indexed=1,
            failed=0,
            index_status=result["index_status"],
        )
        return {"run_id": run["run_id"], **result}
    except HTTPException:
        raise
    except StaleDataError as exc:
        await db.rollback()
        await record_task_run_error(
            "semantic_reindex", run["run_id"], exc,
            trigger="manual", scope="embedding", embedding_id=embedding_id, failed=1,
        )
        raise HTTPException(status_code=409, detail="原文已变化，请刷新后重新索引") from exc
    except ValueError as exc:
        await db.rollback()
        await record_task_run_error(
            "semantic_reindex",
            run["run_id"],
            exc,
            trigger="manual",
            scope="embedding",
            embedding_id=embedding_id,
            failed=1,
        )
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        await db.rollback()
        await record_task_run_error(
            "semantic_reindex",
            run["run_id"],
            exc,
            trigger="manual",
            scope="embedding",
            embedding_id=embedding_id,
            failed=1,
        )
        raise HTTPException(status_code=500, detail=f"语义分块重试失败: {exc}")
