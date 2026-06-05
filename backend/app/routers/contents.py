"""
功能描述：内容管理相关 API
包含：分享创建、内容增删改查、机器人对接、审批流
调用方式：详见各接口文档
"""
from typing import List, Optional
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Query, BackgroundTasks
from sqlalchemy import select, desc, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models import (
    Content,
    ContentEmbedding,
    ContentQueueItem,
    ContentStatus,
    PushedRecord,
    QueueItemStatus,
    Platform,
    ReviewStatus,
    ContentSource,
)
from app.schemas import (
    ShareRequest, ShareResponse, ContentDetail,
    ShareCardListResponse, ContentListItemResponse, ContentListItem,
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
from app.services.background_task_state import (
    record_task_run_error,
    record_task_run_started,
    record_task_run_success,
)
from app.media.extractor import sanitize_media_urls
from app.adapters.utils import ensure_title
from app.services.settings_service import get_setting_value

router = APIRouter()


def _status_counts(rows) -> dict[str, int]:
    counts: dict[str, int] = {}
    for status, count in rows:
        key = status.value if hasattr(status, "value") else str(status or "unknown")
        counts[key] = int(count or 0)
    return counts


async def _build_processing_status(content: Content, db: AsyncSession) -> dict:
    summary_enabled = bool(await get_setting_value("enable_auto_summary", settings.enable_auto_summary))
    summary_key = await get_setting_value("summary_api_key")
    has_summary = bool((content.summary or "").strip())
    has_chunks = bool(
        isinstance(content.rich_payload, dict)
        and content.rich_payload.get("chunks")
    )

    if has_summary or has_chunks:
        summary_status = "success"
        summary_message = "摘要或 RAG 分块已生成"
    elif content.status != ContentStatus.PARSE_SUCCESS:
        summary_status = "waiting_parse"
        summary_message = "等待解析成功后生成摘要"
    elif not summary_enabled:
        summary_status = "disabled"
        summary_message = "自动摘要已关闭"
    elif not summary_key:
        summary_status = "unavailable"
        summary_message = "摘要模型密钥未配置"
    else:
        summary_status = "pending"
        summary_message = "尚未生成摘要"

    embedding_rows = (
        await db.execute(
            select(ContentEmbedding.index_status, func.count(ContentEmbedding.id))
            .where(ContentEmbedding.content_id == content.id)
            .group_by(ContentEmbedding.index_status)
        )
    ).all()
    embedding_counts = _status_counts(embedding_rows)
    if embedding_counts.get("indexed", 0) > 0:
        embedding_status = "success"
        embedding_message = f"{embedding_counts['indexed']} 个分块已进入语义索引"
    elif embedding_counts.get("failed", 0) > 0:
        embedding_status = "failed"
        embedding_message = "语义索引生成失败"
    elif embedding_counts.get("pending", 0) > 0 or embedding_counts.get("processing", 0) > 0:
        embedding_status = "pending"
        embedding_message = "语义索引正在生成或排队"
    elif content.status != ContentStatus.PARSE_SUCCESS:
        embedding_status = "waiting_parse"
        embedding_message = "等待解析成功后进入语义索引"
    else:
        embedding_status = "not_indexed"
        embedding_message = "尚未进入语义索引"

    queue_rows = (
        await db.execute(
            select(ContentQueueItem.status, func.count(ContentQueueItem.id))
            .where(ContentQueueItem.content_id == content.id)
            .group_by(ContentQueueItem.status)
        )
    ).all()
    queue_counts = _status_counts(queue_rows)
    pushed_records = int(
        (
            await db.execute(
                select(func.count(PushedRecord.id)).where(PushedRecord.content_id == content.id)
            )
        ).scalar()
        or 0
    )
    queued_count = queue_counts.get(QueueItemStatus.SCHEDULED.value, 0) + queue_counts.get(
        QueueItemStatus.PROCESSING.value,
        0,
    )
    if queued_count > 0:
        distribution_status = "queued"
        distribution_message = f"{queued_count} 条分发队列项待处理"
    elif queue_counts.get(QueueItemStatus.FAILED.value, 0) > 0:
        distribution_status = "failed"
        distribution_message = "存在失败或被过滤的分发队列项"
    elif queue_counts.get(QueueItemStatus.SUCCESS.value, 0) > 0 or pushed_records > 0:
        distribution_status = "pushed"
        distribution_message = "已有分发成功记录"
    else:
        distribution_status = "not_matched"
        distribution_message = "暂未匹配分发规则"

    return {
        "content_id": content.id,
        "stages": [
            {
                "key": "summary",
                "label": "摘要",
                "status": summary_status,
                "message": summary_message,
                "details": {
                    "summary_present": has_summary,
                    "chunks_present": has_chunks,
                    "auto_summary_enabled": summary_enabled,
                },
            },
            {
                "key": "semantic_index",
                "label": "语义索引",
                "status": embedding_status,
                "message": embedding_message,
                "details": {"counts": embedding_counts},
            },
            {
                "key": "distribution",
                "label": "分发",
                "status": distribution_status,
                "message": distribution_message,
                "details": {
                    "queue_counts": queue_counts,
                    "pushed_records": pushed_records,
                },
            },
        ],
    }


async def _run_reparse_job(content_id: int, run_id: str, *, force: bool) -> None:
    try:
        ok = await worker.retry_parse(content_id, force=force)
        if ok:
            await record_task_run_success(
                "content_reparse",
                run_id,
                content_id=content_id,
                force=force,
            )
            return

        await record_task_run_error(
            "content_reparse",
            run_id,
            "Re-parse failed or reached retry limit",
            content_id=content_id,
            force=force,
        )
    except Exception as exc:
        await record_task_run_error(
            "content_reparse",
            run_id,
            exc,
            content_id=content_id,
            force=force,
        )
        raise

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

# --- 分享 ---

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

# --- 内容 增删改查 ---

@router.get("/contents", response_model=ContentListItemResponse)
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
    
    items_pydantic = [
        ContentListItem.model_validate(c)
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

    sanitized_media_urls = sanitize_media_urls(
        content.media_urls,
        author_avatar_url=content.author_avatar_url,
    )
    if sanitized_media_urls != (content.media_urls or []):
        content.media_urls = sanitized_media_urls
        await db.commit()
        await db.refresh(content)
        
    base_url = settings.base_url or "http://localhost:8000"
    return transform_content_detail(ContentDetail.model_validate(content), base_url)


@router.get("/contents/{content_id}/processing-status")
async def get_content_processing_status(
    content_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """Expose post-ingest processing status for the content detail UI."""
    result = await db.execute(select(Content).where(Content.id == content_id))
    content = result.scalar_one_or_none()
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")
    return await _build_processing_status(content, db)


@router.patch("/contents/{content_id}", response_model=ContentDetail)
async def update_content(
    content_id: int,
    request: ContentUpdate,
    service: ContentService = Depends(get_content_service),
    _: None = Depends(require_api_token),
):
    """修改内容"""
    # exclude_unset=True：只更新请求体里显式出现的字段，
    # 这样 layout_type_override=null 可以正确清除 override，
    # 而完全不传的字段不会被覆盖为 None。
    updates = {
        k: v for k, v in request.model_dump(exclude_unset=True).items()
        if v is not None or k == "layout_type_override"
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
    run = await record_task_run_started(
        "content_summary",
        content_id=content_id,
        force=force,
        trigger="manual",
    )
    try:
        content = await generate_summary_for_content(db, content_id, force=force)
        chunks = (
            content.rich_payload.get("chunks", [])
            if isinstance(content.rich_payload, dict)
            else []
        )
        await record_task_run_success(
            "content_summary",
            run["run_id"],
            content_id=content_id,
            force=force,
            summary_present=bool(content.summary),
            chunk_count=len(chunks) if isinstance(chunks, list) else 0,
            tag_count=len(content.tags or []),
        )
        return {"summary": content.summary, "content_id": content_id, "run_id": run["run_id"]}
    except ValueError as e:
        await record_task_run_error(
            "content_summary",
            run["run_id"],
            e,
            content_id=content_id,
            force=force,
        )
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        await record_task_run_error(
            "content_summary",
            run["run_id"],
            e,
            content_id=content_id,
            force=force,
        )
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

    run = await record_task_run_started(
        "content_reparse",
        content_id=content_id,
        force=True,
        trigger="manual",
    )
    background_tasks.add_task(
        _run_reparse_job,
        content_id,
        run["run_id"],
        force=True,
    )
    return {
        "status": "processing",
        "content_id": content_id,
        "run_id": run["run_id"],
        "message": "Re-parsing started in background",
    }

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

# --- 卡片与预览 ---

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
    contents, total = await repo.list_cards(
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
            "status": c.status,
            "clean_url": c.clean_url,
            "content_type": c.content_type,
            "effective_layout_type": compute_effective_layout_type(c),
            "title": ensure_title(c.title, None),
            "author_name": c.author_name,
            "author_id": c.author_id,
            "author_avatar_url": transform_media_url(compute_author_avatar_url(c), base_url),
            "cover_url": cover_url,
            "thumbnail_url": thumbnail_url,
            "cover_color": c.cover_color,
            "tags": c.tags or [],
            "is_nsfw": c.is_nsfw or False,
            "discovery_state": c.discovery_state.value if c.discovery_state else None,
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
        "status": c.status,
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
        "discovery_state": c.discovery_state.value if c.discovery_state else None,
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
