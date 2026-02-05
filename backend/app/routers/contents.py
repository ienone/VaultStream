"""
功能描述：内容管理相关 API
包含：分享创建、内容增删改查、机器人对接、审批流
调用方式：详见各接口文档
"""
from typing import List, Optional
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Query, BackgroundTasks
from sqlalchemy import select, and_, func, desc
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.concurrency import run_in_threadpool
import mimetypes
import os

from app.core.database import get_db
from app.models import Content, ContentStatus, PushedRecord, Platform, ReviewStatus, WeiboUser, ContentSource
from app.schemas import (
    ShareRequest, ShareResponse, ContentDetail,
    GetContentRequest, MarkPushedRequest, ShareCardListResponse, ContentListResponse,
    ContentUpdate, ShareCardPreview, OptimizedMedia, ReviewAction, BatchReviewRequest,
    PushedRecordResponse, WeiboUserResponse
)
from app.core.logging import logger
from app.core.config import settings
from app.worker import worker
from app.core.storage import get_storage_backend, LocalStorageBackend
from app.adapters import AdapterFactory

from app.core.dependencies import require_api_token, get_content_service, get_content_repo
from app.services.content_service import ContentService
from app.repositories.content_repository import ContentRepository
from app.core.events import event_bus

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

def _transform_media_url(url: Optional[str], base_url: str) -> Optional[str]:
    """将 local:// 协议的 URL 转换为 HTTP 代理 URL"""
    if url and url.startswith("local://"):
        key = url.replace("local://", "")
        return f"{base_url}/api/v1/media/{key}"
    return url

def _transform_content_detail(content: ContentDetail, base_url: str) -> ContentDetail:
    """转换内容详情中的所有媒体链接"""
    content.cover_url = _transform_media_url(content.cover_url, base_url)
    content.author_avatar_url = _transform_media_url(content.author_avatar_url, base_url)
    if content.media_urls:
        content.media_urls = [_transform_media_url(u, base_url) for u in content.media_urls if u]
    
    # Phase 7: 转换 top_answers 中的头像/封面
    if content.top_answers:
        for ans in content.top_answers:
            if ans.get("author_avatar_url"):
                ans["author_avatar_url"] = _transform_media_url(ans["author_avatar_url"], base_url)
            if ans.get("cover_url"):
                ans["cover_url"] = _transform_media_url(ans["cover_url"], base_url)
    
    # 转换 associated_question 中的封面
    if content.associated_question:
        if content.associated_question.get("cover_url"):
            content.associated_question["cover_url"] = _transform_media_url(
                content.associated_question["cover_url"], base_url
            )
                
    # 转换 Markdown 正文中的 local:// 图片链接 (完整处理)
    if content.description and "local://" in content.description:
        import re
        def replacer(match):
            key = match.group(1)
            return f"{base_url}/api/v1/media/{key}"
        local_pattern = r'local://([a-zA-Z0-9_/.-]+)'
        content.description = re.sub(local_pattern, replacer, content.description)

    return content

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

@router.get("/tags")
async def list_all_tags(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取所有标签及其计数"""
    result = await db.execute(select(Content.tags).where(Content.tags != None))
    all_tag_lists = result.scalars().all()
    
    tag_counts = {}
    for tags in all_tag_lists:
        if isinstance(tags, list):
            for t in tags:
                tag_counts[t] = tag_counts.get(t, 0) + 1
                
    return sorted(
        [{"name": k, "count": v} for k, v in tag_counts.items()],
        key=lambda x: x["count"],
        reverse=True
    )

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
    
    # 转换 Pydantic 模型并处理 local:// URL
    base_url = settings.base_url or "http://localhost:8000"
    items_pydantic = [
        _transform_content_detail(ContentDetail.model_validate(c), base_url)
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
    return _transform_content_detail(ContentDetail.model_validate(content), base_url)

@router.patch("/contents/{content_id}", response_model=ContentDetail)
async def update_content(
    content_id: int,
    request: ContentUpdate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """修改内容"""
    result = await db.execute(select(Content).where(Content.id == content_id))
    content = result.scalar_one_or_none()
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")
    
    if request.tags is not None:
        content.tags = request.tags
    if request.title is not None:
        content.title = request.title
    if request.description is not None:
        content.description = request.description
    if request.author_name is not None:
        content.author_name = request.author_name
    if request.cover_url is not None:
        if content.cover_url != request.cover_url:
            content.cover_url = request.cover_url
            from app.media.color import extract_cover_color
            content.cover_color = await extract_cover_color(content.cover_url)
    if request.is_nsfw is not None:
        content.is_nsfw = request.is_nsfw
    if request.status is not None:
        content.status = request.status
    if request.review_status is not None:
        content.review_status = request.review_status
    if request.review_note is not None:
        content.review_note = request.review_note
    if request.reviewed_by is not None:
        content.reviewed_by = request.reviewed_by
    if request.layout_type_override is not None:
        content.layout_type_override = request.layout_type_override
        
    await db.commit()
    await db.refresh(content)
    
    # 广播更新事件
    await event_bus.publish("content_updated", {
        "id": content.id,
        "title": content.title,
        "status": content.status.value if content.status else None,
        "platform": content.platform.value if content.platform else None,
    })
    
    base_url = settings.base_url or "http://localhost:8000"
    return _transform_content_detail(ContentDetail.model_validate(content), base_url)

@router.delete("/contents/{content_id}")
async def delete_content(
    content_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """删除内容 (仅数据库记录)"""
    result = await db.execute(select(Content).where(Content.id == content_id))
    content = result.scalar_one_or_none()
    
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")
    
    await db.execute(select(ContentSource).where(ContentSource.content_id == content_id))
    await db.execute(ContentSource.__table__.delete().where(ContentSource.content_id == content_id))
    await db.execute(PushedRecord.__table__.delete().where(PushedRecord.content_id == content_id))
    
    await db.delete(content)
    await db.commit()
    
    logger.info(f"内容已删除: content_id={content_id}")
    
    # 广播删除事件
    await event_bus.publish("content_deleted", {"id": content_id})
    
    return {"status": "deleted", "content_id": content_id}

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

# --- Bot & Distribution Support ---

@router.post("/bot/get-content", response_model=List[ContentDetail])
async def get_content_for_bot(
    request: GetContentRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """供机器人调用：获取待分发的内容"""
    try:
        subquery = (
            select(PushedRecord.content_id)
            .where(PushedRecord.target_platform == request.target_platform)
        )
        
        query = select(Content).where(
            and_(
                Content.status.in_([ContentStatus.PULLED, ContentStatus.DISTRIBUTED]),
                ~Content.id.in_(subquery)
            )
        )
        
        if request.tag and isinstance(request.tag, str) and request.tag.strip():
            tag_value = request.tag.strip()
            query = query.where(Content.tags.contains([tag_value]))
        
        if hasattr(request, 'platform') and request.platform:
            try:
                platform_enum = Platform(request.platform)
                query = query.where(Content.platform == platform_enum)
            except ValueError:
                raise HTTPException(status_code=400, detail=f"无效的平台: {request.platform}")
        
        query = query.order_by(Content.created_at.desc()).limit(request.limit)
        
        result = await db.execute(query)
        contents = result.scalars().all()
    except Exception as e:
        logger.exception("查询待推送内容失败")
        raise HTTPException(status_code=500, detail=f"查询失败: {str(e)[:200]}")

    return [ContentDetail.model_validate(c) for c in contents]

@router.post("/bot/mark-pushed")
async def mark_content_pushed(
    request: MarkPushedRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """供机器人调用：标记内容已推送"""
    try:
        result = await db.execute(select(Content).where(Content.id == request.content_id))
        content = result.scalar_one_or_none()
        
        if not content:
            raise HTTPException(status_code=404, detail="内容不存在")
        
        existing = await db.execute(
            select(PushedRecord).where(
                and_(
                    PushedRecord.content_id == request.content_id,
                    PushedRecord.target_id == request.target_id
                )
            )
        )
        existing_record = existing.scalar_one_or_none()
        
        if existing_record:
            if request.message_id:
                existing_record.message_id = request.message_id
                existing_record.push_status = "success"
                await db.commit()
            return {"success": True, "message": "已更新", "record_id": existing_record.id}
        
        pushed_record = PushedRecord(
            content_id=request.content_id,
            target_platform=request.target_platform,
            target_id=request.target_id,
            message_id=request.message_id,
            push_status="success"
        )
        db.add(pushed_record)
        await db.commit()
        
        # 发送 SSE 事件通知前端
        from app.core.events import event_bus
        await event_bus.publish("content_pushed", {
            "content_id": request.content_id,
            "target_id": request.target_id,
            "target_platform": request.target_platform,
            "message_id": request.message_id,
        })
        
        return {"success": True, "message": "标记成功", "record_id": pushed_record.id}
        
    except Exception as e:
        logger.error(f"标记推送失败: {e}")
        raise HTTPException(status_code=500, detail=str(e))

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
        cover_url = _transform_media_url(c.cover_url, base_url)
        # 生成缩略图URL (添加 ?size=thumb 参数)
        thumbnail_url = None
        if cover_url and "/api/v1/media/" in cover_url:
            thumbnail_url = f"{cover_url}?size=thumb"
        
        # 计算有效布局类型
        effective_layout = c.effective_layout_type.value if c.effective_layout_type else None
        
        items.append({
            "id": c.id,
            "platform": c.platform,
            "url": c.url,
            "clean_url": c.clean_url,
            "content_type": c.content_type,
            "effective_layout_type": effective_layout,
            "title": c.display_title,  # 使用 display_title（自动从正文生成标题）
            "author_name": c.author_name,
            "author_id": c.author_id,
            "author_avatar_url": _transform_media_url(c.author_avatar_url, base_url),
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


@router.post("/cards/{card_id}/review")
async def review_card(
    card_id: int,
    action: ReviewAction,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """审批单个卡片（轻量级接口）"""
    from app.distribution.engine import DistributionEngine
    result = await db.execute(select(Content).where(Content.id == card_id))
    content = result.scalar_one_or_none()
    if not content:
        raise HTTPException(status_code=404, detail="Card not found")
    if action.action not in ["approve", "reject"]:
        raise HTTPException(status_code=400, detail="Invalid action")
    
    is_approve = action.action == "approve"
    content.review_status = ReviewStatus.APPROVED if is_approve else ReviewStatus.REJECTED
    content.reviewed_at = datetime.utcnow()
    content.reviewed_by = action.reviewed_by
    content.review_note = action.note
    
    if is_approve:
        engine = DistributionEngine(db)
        content.scheduled_at = await engine.calculate_scheduled_at(content)
    else:
        content.scheduled_at = None
    
    await db.commit()
    return {"id": content.id, "review_status": content.review_status.value, "scheduled_at": content.scheduled_at}


@router.post("/cards/batch-review")
async def batch_review_cards(
    request: BatchReviewRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """批量审批卡片（轻量级接口）"""
    from app.distribution.engine import DistributionEngine
    if request.action not in ["approve", "reject"]:
        raise HTTPException(status_code=400, detail="Invalid action")
    
    is_approve = request.action == "approve"
    review_status = ReviewStatus.APPROVED if is_approve else ReviewStatus.REJECTED
    
    result = await db.execute(select(Content).where(Content.id.in_(request.content_ids)))
    contents = result.scalars().all()
    if not contents:
        raise HTTPException(status_code=404, detail="No cards found")
    
    engine = DistributionEngine(db)
    for content in contents:
        content.review_status = review_status
        content.reviewed_at = datetime.utcnow()
        content.reviewed_by = request.reviewed_by
        content.review_note = request.note
        if is_approve:
            content.scheduled_at = await engine.calculate_scheduled_at(content)
        else:
            content.scheduled_at = None
    
    await db.commit()
    return {"updated": len(contents), "action": request.action}


@router.get("/contents/{content_id}/preview", response_model=ShareCardPreview)
async def get_content_preview(
    content_id: int,
    db: AsyncSession = Depends(get_db),
    storage: LocalStorageBackend = Depends(get_storage_backend),
    _: None = Depends(require_api_token),
):
    """获取内容的分享卡片预览"""
    result = await db.execute(select(Content).where(Content.id == content_id))
    content = result.scalar_one_or_none()
    
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")
    
    optimized_media = []
    base_url = settings.base_url or "http://localhost:8000"
    
    if content.media_urls:
        for media_url in content.media_urls:
            if media_url.startswith("local://"):
                key = media_url.replace("local://", "")
                proxy_url = f"{base_url}/api/v1/media/{key}"
                file_path = storage._full_path(key)
                size_bytes = os.path.getsize(file_path) if os.path.exists(file_path) else None
                mime_type, _ = mimetypes.guess_type(key)
                media_type = "image" if mime_type and mime_type.startswith("image/") else "video"
                optimized_media.append(OptimizedMedia(type=media_type, url=proxy_url, size_bytes=size_bytes))
            else:
                optimized_media.append(OptimizedMedia(type="image", url=media_url))
    
    summary = None
    if content.description:
        summary = content.description[:200] + ("..." if len(content.description) > 200 else "")
    
    return ShareCardPreview(
        id=content.id,
        platform=content.platform,
        title=content.title,
        summary=summary,
        author_name=content.author_name,
        cover_url=content.cover_url,
        optimized_media=optimized_media,
        source_url=content.clean_url or content.url,
        tags=content.tags or [],
        published_at=content.published_at,
        view_count=content.view_count,
        like_count=content.like_count
    )

# --- Reviews ---

@router.post("/contents/{content_id}/review")
async def review_content(
    content_id: int,
    action: ReviewAction,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """审批单个内容"""
    from app.distribution.engine import DistributionEngine
    result = await db.execute(select(Content).where(Content.id == content_id))
    content = result.scalar_one_or_none()
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")
    if action.action not in ["approve", "reject"]:
        raise HTTPException(status_code=400, detail="Invalid action")
    
    is_approve = action.action == "approve"
    content.review_status = ReviewStatus.APPROVED if is_approve else ReviewStatus.REJECTED
    content.reviewed_at = datetime.utcnow()
    content.reviewed_by = action.reviewed_by
    content.review_note = action.note
    
    if is_approve:
        engine = DistributionEngine(db)
        content.scheduled_at = await engine.calculate_scheduled_at(content)
    else:
        content.scheduled_at = None
        
    await db.commit()
    await db.refresh(content)
    return {"id": content.id, "review_status": content.review_status, "reviewed_at": content.reviewed_at, "scheduled_at": content.scheduled_at}

@router.post("/contents/batch-review")
async def batch_review_contents(
    request: BatchReviewRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """批量审批内容"""
    from app.distribution.engine import DistributionEngine
    if request.action not in ["approve", "reject"]:
        raise HTTPException(status_code=400, detail="Invalid action")
    
    is_approve = request.action == "approve"
    review_status = ReviewStatus.APPROVED if is_approve else ReviewStatus.REJECTED
    
    result = await db.execute(select(Content).where(Content.id.in_(request.content_ids)))
    contents = result.scalars().all()
    if not contents:
        raise HTTPException(status_code=404, detail="No contents found")
    
    engine = DistributionEngine(db)
    for content in contents:
        content.review_status = review_status
        content.reviewed_at = datetime.utcnow()
        content.reviewed_by = request.reviewed_by
        content.review_note = request.note
        if is_approve:
            content.scheduled_at = await engine.calculate_scheduled_at(content)
        else:
            content.scheduled_at = None
    
    await db.commit()
    return {"updated": len(contents), "action": request.action, "content_ids": request.content_ids}

@router.get("/contents/pending-review", response_model=ContentListResponse)
async def get_pending_review_contents(
    page: int = Query(1, ge=1),
    size: int = Query(20, ge=1, le=100),
    platform: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取待审批内容列表"""
    query = select(Content).where(Content.review_status == ReviewStatus.PENDING)
    if platform:
        try:
            platform_enum = Platform(platform)
            query = query.where(Content.platform == platform_enum)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid platform")
    
    count_result = await db.execute(select(func.count()).select_from(query.subquery()))
    total = count_result.scalar() or 0
    
    offset = (page - 1) * size
    query = query.order_by(desc(Content.created_at)).offset(offset).limit(size)
    result = await db.execute(query)
    contents = result.scalars().all()
    
    return ContentListResponse(
        items=[ContentDetail.model_validate(c) for c in contents],
        total=total,
        page=page,
        size=size,
        has_more=offset + size < total
    )

# --- Platform Specific (Weibo) ---

@router.post("/weibo/users/{uid}/archive", response_model=WeiboUserResponse)
async def archive_weibo_user(
    uid: str,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """存档微博用户数据"""
    try:
        adapter = AdapterFactory.create(Platform.WEIBO)
        if not hasattr(adapter, 'fetch_user_profile'):
             raise HTTPException(status_code=500, detail="Adapter does not support user fetching")
        
        user_data = await run_in_threadpool(adapter.fetch_user_profile, uid)
        
        result = await db.execute(select(WeiboUser).where(WeiboUser.platform_id == uid))
        db_user = result.scalar_one_or_none()
        
        if not db_user:
            db_user = WeiboUser(
                platform_id=uid,
                nick_name=user_data.get('nick_name', ''),
                avatar_hd=user_data.get('avatar_hd', ''),
                description=user_data.get('description', ''),
                followers_count=user_data.get('followers_count', 0),
                friends_count=user_data.get('friends_count', 0),
                statuses_count=user_data.get('statuses_count', 0),
                verified=user_data.get('verified', False),
                verified_type=user_data.get('verified_type'),
                verified_reason=user_data.get('verified_reason'),
                gender=user_data.get('gender', ''),
                location=user_data.get('location', ''),
                raw_data=user_data.get('raw_data', {})
            )
            db.add(db_user)
        else:
            db_user.nick_name = user_data.get('nick_name', '')
            db_user.avatar_hd = user_data.get('avatar_hd', '')
            db_user.description = user_data.get('description', '')
            db_user.followers_count = user_data.get('followers_count', 0)
            db_user.friends_count = user_data.get('friends_count', 0)
            db_user.statuses_count = user_data.get('statuses_count', 0)
            db_user.verified = user_data.get('verified', False)
            db_user.verified_type = user_data.get('verified_type')
            db_user.verified_reason = user_data.get('verified_reason')
            db_user.gender = user_data.get('gender', '')
            db_user.location = user_data.get('location', '')
            db_user.raw_data = user_data.get('raw_data', {})
            
        await db.commit()
        await db.refresh(db_user)
        return db_user

    except Exception as e:
        logger.exception(f"Weibo user archive failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))
