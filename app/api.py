"""
FastAPI 路由
"""
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession
from loguru import logger

from app.database import get_db
from app.models import Content, ContentStatus, PushedRecord, Platform
from app.schemas import (
    ShareRequest, ShareResponse, ContentDetail,
    GetContentRequest, MarkPushedRequest
)
from app.queue import task_queue
from app.adapters import AdapterFactory

router = APIRouter()


@router.post("/shares", response_model=ShareResponse)
async def create_share(
    share: ShareRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    创建分享
    
    接收一个URL，识别平台，创建内容记录并加入解析队列
    """
    try:
        # 检测平台
        platform = AdapterFactory.detect_platform(share.url)
        if not platform:
            raise HTTPException(status_code=400, detail="无法识别的平台URL")
        
        # 创建内容记录
        content = Content(
            platform=platform,
            url=share.url,
            tags=share.tags,
            source=share.source,
            is_nsfw=share.is_nsfw,
            status=ContentStatus.UNPROCESSED
        )
        
        db.add(content)
        await db.commit()
        await db.refresh(content)
        
        # 加入解析队列
        await task_queue.enqueue({
            'content_id': content.id,
            'action': 'parse'
        })
        
        logger.info(f"创建分享成功: {content.id} - {share.url}")
        
        return ShareResponse(
            id=content.id,
            platform=content.platform,
            url=content.url,
            status=content.status,
            created_at=content.created_at
        )
        
    except Exception as e:
        logger.error(f"创建分享失败: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/contents/{content_id}", response_model=ContentDetail)
async def get_content(
    content_id: int,
    db: AsyncSession = Depends(get_db)
):
    """获取内容详情"""
    result = await db.execute(
        select(Content).where(Content.id == content_id)
    )
    content = result.scalar_one_or_none()
    
    if not content:
        raise HTTPException(status_code=404, detail="内容不存在")
    
    return ContentDetail.model_validate(content)


@router.get("/contents", response_model=List[ContentDetail])
async def list_contents(
    status: Optional[ContentStatus] = None,
    platform: Optional[Platform] = None,
    tag: Optional[str] = None,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db)
):
    """列出内容"""
    query = select(Content)
    
    # 添加过滤条件
    conditions = []
    if status:
        conditions.append(Content.status == status)
    if platform:
        conditions.append(Content.platform == platform)
    if tag:
        conditions.append(Content.tags.contains([tag]))
    
    if conditions:
        query = query.where(and_(*conditions))
    
    query = query.order_by(Content.created_at.desc()).limit(limit).offset(offset)
    
    result = await db.execute(query)
    contents = result.scalars().all()
    
    return [ContentDetail.model_validate(c) for c in contents]


@router.post("/bot/get-content", response_model=List[ContentDetail])
async def get_content_for_bot(
    request: GetContentRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    供机器人调用：获取待分发的内容
    
    返回未推送到指定平台的内容
    """
    # 构建查询：状态为PULLED且未推送到目标平台
    subquery = (
        select(PushedRecord.content_id)
        .where(PushedRecord.target_platform == request.target_platform)
    )
    
    query = select(Content).where(
        and_(
            Content.status == ContentStatus.PULLED,
            ~Content.id.in_(subquery)
        )
    )
    
    # 按标签过滤
    if request.tag:
        query = query.where(Content.tags.contains([request.tag]))
    
    query = query.order_by(Content.created_at.desc()).limit(request.limit)
    
    result = await db.execute(query)
    contents = result.scalars().all()
    
    return [ContentDetail.model_validate(c) for c in contents]


@router.post("/bot/mark-pushed")
async def mark_content_pushed(
    request: MarkPushedRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    供机器人调用：标记内容已推送
    
    记录推送历史，更新内容状态
    """
    try:
        # 检查内容是否存在
        result = await db.execute(
            select(Content).where(Content.id == request.content_id)
        )
        content = result.scalar_one_or_none()
        
        if not content:
            raise HTTPException(status_code=404, detail="内容不存在")
        
        # 检查是否已推送
        existing = await db.execute(
            select(PushedRecord).where(
                and_(
                    PushedRecord.content_id == request.content_id,
                    PushedRecord.target_platform == request.target_platform
                )
            )
        )
        if existing.scalar_one_or_none():
            raise HTTPException(status_code=400, detail="已标记为推送")
        
        # 创建推送记录
        pushed_record = PushedRecord(
            content_id=request.content_id,
            target_platform=request.target_platform,
            message_id=request.message_id
        )
        db.add(pushed_record)
        
        # 更新内容状态
        content.status = ContentStatus.DISTRIBUTED
        
        await db.commit()
        
        logger.info(f"标记推送成功: {request.content_id} -> {request.target_platform}")
        
        return {"success": True, "message": "标记成功"}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"标记推送失败: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/health")
async def health_check():
    """健康检查"""
    queue_size = await task_queue.get_queue_size()
    return {
        "status": "ok",
        "queue_size": queue_size
    }
