"""
功能描述：内容管理相关 API
包含：分享创建、内容增删改查、机器人对接、审批流
调用方式：详见各接口文档
"""
from typing import List, Optional
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Query, BackgroundTasks
from sqlalchemy import select, desc
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models import Content, ContentStatus, PushedRecord, Platform, ReviewStatus, ContentSource
from app.schemas import (
    ShareRequest, ShareResponse, ContentDetail,
    ShareCardListResponse, ContentListResponse,
    ContentUpdate, ReviewAction, BatchReviewRequest,
    PushedRecordResponse
)
from app.core.logging import logger
from app.core.config import settings
from app.tasks import worker
from app.core.dependencies import require_api_token, get_content_service, get_content_repo
from app.services.content_service import ContentService
from app.repositories.content_repository import ContentRepository
from app.services.content_presenter import (
    compute_effective_layout_type, compute_display_title, compute_author_avatar_url,
    transform_media_url, transform_content_detail,
)

router = APIRouter()

def _parse_list_param(values: Optional[List[str]]) -> Optional[List[str]]:
    """处理 FastAPI List[str] 参数，支持逗号分隔或多个相同 Key"""
    if not values:
        return None
    result = []
    for v in values:
        if "," in v:
            result.extend([i.strip() for i in v.split(",") if i.strip()])
        else:
            result.append(v)
    return result if result else None

# --- Sharing ---

@router.post("/shares", response_model=ShareResponse)
async def create_share(
    share: ShareRequest,
    service: ContentService = Depends(get_content_service),
    _: None = Depends(require_api_token),
):
    """创建分享"""
    try:
        content = await service.create_share(
            url=share.url,
            tags=share.tags,
            tags_text=share.tags_text,
            source_name=share.source,
            note=share.note,
            is_nsfw=share.is_nsfw,
            client_context=share.client_context,
            layout_type_override=share.layout_type_override
        )
        return ShareResponse(
            id=content.id,
            platform=content.platform,
            url=content.url,
            status=content.status,
            created_at=content.created_at
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.exception("Failed to create share")
        raise HTTPException(status_code=500, detail="Internal server error")

# --- Content CRUD ---

@router.get("/contents", response_model=ContentListResponse)
async def list_contents(
    page: int = Query(1, ge=1),
    size: int = Query(20, ge=1, le=100),
    platforms: Optional[List[str]] = Query(None, alias="platform"),
    statuses: Optional[List[str]] = Query(None, alias="status"),
    review_status: Optional[ReviewStatus] = Query(None),
    tags: Optional[List[str]] = Query(None, alias="tag"),
    author: Optional[str] = Query(None),
    start_date: Optional[datetime] = Query(None),
    end_date: Optional[datetime] = Query(None),
    q: Optional[str] = Query(None),
    is_nsfw: Optional[bool] = Query(None),
    repo: ContentRepository = Depends(get_content_repo),
    _: None = Depends(require_api_token),
):
    """完整内容列表查询"""
    items, total = await repo.list_contents(
        page=page, 
        size=size, 
        platforms=_parse_list_param(platforms), 
        statuses=_parse_list_param(statuses), 
        review_status=review_status,
        tags=_parse_list_param(tags), 
        author=author, 
        start_date=start_date, 
        end_date=end_date, 
        q=q, 
        is_nsfw=is_nsfw
    )
    
    base_url = settings.base_url or "http://localhost:8000"
    items_pydantic = [
        transform_content_detail(ContentDetail.model_validate(c), base_url)
        for c in items
    ]
    
    return {
        "items": items_pydantic,
        "total": total,
        "page": page,
        "size": size,
        "has_more": total > page * size
    }

@router.get("/contents/{content_id}", response_model=ContentDetail)
async def get_content_detail(
    content_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """内容详情"""
    result = await db.execute(select(Content).where(Content.id == content_id))
    content = result.scalar_one_or_none()
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")
        
    base_url = settings.base_url or "http://localhost:8000"
    return transform_content_detail(ContentDetail.model_validate(content), base_url)

@router.patch("/contents/{content_id}", response_model=ContentDetail)
async def update_content(
    content_id: int,
    request: ContentUpdate,
    service: ContentService = Depends(get_content_service),
    _: None = Depends(require_api_token),
):
    """修改内容"""
    updates = {
        k: v for k, v in {
            "tags": request.tags,
            "title": request.title,
            "body": request.body,
            "author_name": request.author_name,
            "cover_url": request.cover_url,
            "is_nsfw": request.is_nsfw,
            "status": request.status,
            "review_status": request.review_status,
            "review_note": request.review_note,
            "reviewed_by": request.reviewed_by,
            "layout_type_override": request.layout_type_override,
        }.items() if v is not None
    }
    try:
        content = await service.update_content(content_id, updates)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

    base_url = settings.base_url or "http://localhost:8000"
    return transform_content_detail(ContentDetail.model_validate(content), base_url)

@router.delete("/contents/{content_id}")
async def delete_content(
    content_id: int,
    service: ContentService = Depends(get_content_service),
    _: None = Depends(require_api_token),
):
    """删除内容（含数据库记录和已归档的本地媒体文件）"""
    try:
        return await service.delete_content(content_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

@router.post("/contents/{content_id}/retry")
async def retry_content(
    content_id: int,
    max_retries: int = 3,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """手动触发重试解析"""
    try:
        result = await db.execute(select(Content).where(Content.id == content_id))
        content = result.scalar_one_or_none()

        if not content:
            raise HTTPException(status_code=404, detail="内容不存在")

        ok = await worker.retry_parse(content_id, max_retries=max_retries)

        if not ok:
            raise HTTPException(status_code=500, detail="重试失败或达到最大重试次数")

        await db.refresh(content)
        return {"success": True, "content_id": content_id, "status": content.status}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"重试接口失败: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/contents/{content_id}/generate-summary")
async def generate_content_summary(
    content_id: int,
    force: bool = Query(False, description="强制重新生成（覆盖已有摘要）"),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """为指定内容生成 AI 摘要"""
    from app.services.content_summary_service import generate_summary_for_content
    try:
        content = await generate_summary_for_content(db, content_id, force=force)
        return {"summary": content.summary, "content_id": content_id}
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"摘要生成失败: {e}")

@router.post("/contents/{content_id}/re-parse")
async def re_parse_content(
    content_id: int,
    background_tasks: BackgroundTasks,
    repo: ContentRepository = Depends(get_content_repo),
    _: None = Depends(require_api_token),
):
    """强制重新解析内容 (异步)"""
    content = await repo.get_by_id(content_id)
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")

    background_tasks.add_task(worker.retry_parse, content_id, force=True)
    return {"status": "processing", "content_id": content_id, "message": "Re-parsing started in background"}

@router.get("/pushed-records", response_model=List[PushedRecordResponse])
async def list_pushed_records(
    content_id: Optional[int] = None,
    target_id: Optional[str] = None,
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """查询推送记录"""
    query = select(PushedRecord).order_by(desc(PushedRecord.pushed_at))
    if content_id:
        query = query.where(PushedRecord.content_id == content_id)
    if target_id:
        query = query.where(PushedRecord.target_id == target_id)
    query = query.limit(limit)
    
    result = await db.execute(query)
    records = result.scalars().all()
    return [PushedRecordResponse.model_validate(r) for r in records]

@router.delete("/pushed-records/{record_id}")
async def delete_pushed_record(
    record_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """删除推送记录（允许重推）"""
    result = await db.execute(select(PushedRecord).where(PushedRecord.id == record_id))
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=404, detail="Pushed record not found")
    
    await db.delete(record)
    await db.commit()
    logger.info(f"推送记录已删除: ID {record_id}")
    return {"success": True, "id": record_id}

# --- Cards & Previews ---

@router.get("/cards", response_model=ShareCardListResponse)
async def list_share_cards(
    page: int = Query(1, ge=1),
    size: int = Query(20, ge=1, le=100),
    platforms: Optional[List[str]] = Query(None, alias="platform"),
    statuses: Optional[List[str]] = Query(None, alias="status"),
    review_status: Optional[ReviewStatus] = Query(None),
    tags: Optional[List[str]] = Query(None, alias="tag"),
    author: Optional[str] = Query(None),
    start_date: Optional[datetime] = Query(None),
    end_date: Optional[datetime] = Query(None),
    q: Optional[str] = Query(None),
    repo: ContentRepository = Depends(get_content_repo),
    _: None = Depends(require_api_token),
):
    """轻量级分享卡片列表"""
    contents, total = await repo.list_contents(
        page=page, 
        size=size, 
        platforms=_parse_list_param(platforms), 
        statuses=_parse_list_param(statuses), 
        review_status=review_status,
        tags=_parse_list_param(tags), 
        author=author, 
        start_date=start_date, 
        end_date=end_date, 
        q=q
    )

    base_url = settings.base_url or "http://localhost:8000"
    items = []
    for c in contents:
        cover_url = transform_media_url(c.cover_url, base_url)
        thumbnail_url = None
        if cover_url and "/api/v1/media/" in cover_url:
            thumbnail_url = f"{cover_url}?size=thumb"
        
        items.append({
            "id": c.id,
            "platform": c.platform,
            "url": c.url,
            "clean_url": c.clean_url,
            "content_type": c.content_type,
            "effective_layout_type": compute_effective_layout_type(c),
            "title": compute_display_title(c),
            "author_name": c.author_name,
            "author_id": c.author_id,
            "author_avatar_url": transform_media_url(compute_author_avatar_url(c), base_url),
            "cover_url": cover_url,
            "thumbnail_url": thumbnail_url,
            "cover_color": c.cover_color,
            "tags": c.tags or [],
            "is_nsfw": c.is_nsfw or False,
            "published_at": c.published_at,
            "created_at": c.created_at,
            "review_status": c.review_status,
            "view_count": c.view_count or 0,
            "like_count": c.like_count or 0,
        })

    return {
        "items": items,
        "total": total,
        "page": page,
        "size": size,
        "has_more": total > page * size
    }


@router.get("/cards/{card_id}")
async def get_share_card(
    card_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """单条分享卡片（供 SSE 增量刷新使用）"""
    result = await db.execute(select(Content).where(Content.id == card_id))
    c = result.scalar_one_or_none()
    if not c:
        raise HTTPException(status_code=404, detail="Card not found")

    base_url = settings.base_url or "http://localhost:8000"
    cover_url = transform_media_url(c.cover_url, base_url)
    thumbnail_url = None
    if cover_url and "/api/v1/media/" in cover_url:
        thumbnail_url = f"{cover_url}?size=thumb"

    return {
        "id": c.id,
        "platform": c.platform,
        "url": c.url,
        "clean_url": c.clean_url,
        "content_type": c.content_type,
        "effective_layout_type": compute_effective_layout_type(c),
        "title": compute_display_title(c),
        "author_name": c.author_name,
        "author_id": c.author_id,
        "author_avatar_url": transform_media_url(compute_author_avatar_url(c), base_url),
        "cover_url": cover_url,
        "thumbnail_url": thumbnail_url,
        "cover_color": c.cover_color,
        "tags": c.tags or [],
        "is_nsfw": c.is_nsfw or False,
        "published_at": c.published_at,
        "created_at": c.created_at,
        "review_status": c.review_status,
        "view_count": c.view_count or 0,
        "like_count": c.like_count or 0,
    }


@router.post("/cards/{card_id}/review")
async def review_card(
    card_id: int,
    action: ReviewAction,
    service: ContentService = Depends(get_content_service),
    _: None = Depends(require_api_token),
):
    """审批单个卡片（轻量级接口）"""
    try:
        return await service.review_card(
            card_id, action=action.action,
            reviewed_by=action.reviewed_by, note=action.note,
        )
    except ValueError as e:
        status = 400 if "Invalid" in str(e) else 404
        raise HTTPException(status_code=status, detail=str(e))


@router.post("/cards/batch-review")
async def batch_review_cards(
    request: BatchReviewRequest,
    service: ContentService = Depends(get_content_service),
    _: None = Depends(require_api_token),
):
    """批量审批卡片（轻量级接口）"""
    try:
        return await service.batch_review_cards(
            content_ids=request.content_ids, action=request.action,
            reviewed_by=request.reviewed_by, note=request.note,
        )
    except ValueError as e:
        status = 400 if "Invalid" in str(e) else 404
        raise HTTPException(status_code=status, detail=str(e))
