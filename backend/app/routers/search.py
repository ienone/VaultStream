"""
语义检索 API
"""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import require_api_token
from app.models import Platform
from app.schemas import SemanticSearchResponse, SemanticSearchItem
from app.services.embedding_service import EmbeddingService

router = APIRouter()


@router.get("/search/semantic", response_model=SemanticSearchResponse)
async def semantic_search(
    q: str = Query(..., min_length=1, description="检索关键词"),
    top_k: int = Query(20, ge=1, le=100, description="返回结果数量"),
    platform: Optional[str] = Query(None, description="平台过滤，如 bilibili/zhihu/twitter"),
    date_from: Optional[datetime] = Query(None, description="开始时间（ISO8601）"),
    date_to: Optional[datetime] = Query(None, description="结束时间（ISO8601）"),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    platform_value: Optional[str] = None
    if platform:
        normalized = platform.strip().lower()
        valid_platforms = {p.value for p in Platform}
        if normalized not in valid_platforms:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid platform: {platform}. valid={sorted(valid_platforms)}",
            )
        platform_value = normalized

    svc = EmbeddingService()
    hits = await svc.search(
        query=q,
        top_k=top_k,
        platform=platform_value,
        date_from=date_from,
        date_to=date_to,
        session=db,
    )

    results = [
        SemanticSearchItem(
            content_id=hit.content.id,
            score=float(hit.score),
            match_source=hit.match_source,
            platform=hit.content.platform.value if hit.content.platform else "",
            url=hit.content.url,
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
        results=results,
    )
