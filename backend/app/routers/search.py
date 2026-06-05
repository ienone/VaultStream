"""
语义检索 API
"""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal
from app.core.database import get_db
from app.core.dependencies import require_api_token
from app.models import ContentStatus, Platform
from app.schemas import (
    SemanticIndexStatusResponse,
    SemanticReindexRequest,
    SemanticReindexResponse,
    SemanticSearchResponse,
    SemanticSearchItem,
)
from app.services.embedding_service import EmbeddingService
from app.services.background_task_state import (
    record_task_run_error,
    record_task_run_started,
    record_task_run_success,
)

router = APIRouter()


def _parse_list_param(values: Optional[list[str]]) -> list[str] | None:
    if not values:
        return None
    parsed: list[str] = []
    for value in values:
        if "," in value:
            parsed.extend(part.strip() for part in value.split(",") if part.strip())
        elif value.strip():
            parsed.append(value.strip())
    return parsed or None


@router.get("/search/semantic", response_model=SemanticSearchResponse)
async def semantic_search(
    q: str = Query(..., min_length=1, description="检索关键词"),
    top_k: int = Query(20, ge=1, le=100, description="返回结果数量"),
    platforms: Optional[list[str]] = Query(None, alias="platform", description="平台过滤，如 bilibili/zhihu/twitter"),
    statuses: Optional[list[str]] = Query(None, alias="status", description="内容处理状态过滤"),
    tags: Optional[list[str]] = Query(None, alias="tag", description="标签过滤"),
    author: Optional[str] = Query(None, description="作者名关键词"),
    date_from: Optional[datetime] = Query(None, description="开始时间（ISO8601）"),
    date_to: Optional[datetime] = Query(None, description="结束时间（ISO8601）"),
    scope: str = Query("library", description="检索范围：library/discovery/all"),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    platform_values = _parse_list_param(platforms)
    if platform_values:
        valid_platforms = {p.value for p in Platform}
        normalized_platforms = [platform.strip().lower() for platform in platform_values]
        invalid_platforms = [platform for platform in normalized_platforms if platform not in valid_platforms]
        if invalid_platforms:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid platform: {invalid_platforms[0]}. valid={sorted(valid_platforms)}",
            )
        platform_values = normalized_platforms

    status_values = _parse_list_param(statuses)
    if status_values:
        valid_statuses = {s.value for s in ContentStatus}
        normalized_statuses = [status.strip().lower() for status in status_values]
        invalid_statuses = [status for status in normalized_statuses if status not in valid_statuses]
        if invalid_statuses:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid status: {invalid_statuses[0]}. valid={sorted(valid_statuses)}",
            )
        status_values = normalized_statuses

    tag_values = _parse_list_param(tags)
    normalized_scope = scope.strip().lower()
    if normalized_scope not in {"library", "discovery", "all"}:
        raise HTTPException(status_code=400, detail="scope must be library, discovery or all")

    svc = EmbeddingService()
    hits = await svc.search(
        query=q,
        top_k=top_k,
        platforms=platform_values,
        statuses=status_values,
        tags=tag_values,
        author=author.strip() if author and author.strip() else None,
        date_from=date_from,
        date_to=date_to,
        scope=normalized_scope,
        session=db,
    )

    results = [
        SemanticSearchItem(
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
            title=hit.content.title,
            summary=hit.content.summary,
            author_name=hit.content.author_name,
            cover_url=hit.content.cover_url,
            tags=(hit.content.tags or []),
            created_at=hit.content.created_at,
            published_at=hit.content.published_at,
        )
        for hit in hits
    ]

    return SemanticSearchResponse(
        query=q,
        top_k=top_k,
        scope=normalized_scope,
        results=results,
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


@router.post("/search/semantic/embeddings/{embedding_id}/retry")
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
