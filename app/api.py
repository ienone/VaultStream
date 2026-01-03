"""
FastAPI 路由
"""
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, Header
from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession
from app.logging import logger, log_context

from app.database import get_db
from app.models import Content, ContentStatus, PushedRecord, Platform, ContentSource
from app.schemas import (
    ShareRequest, ShareResponse, ContentDetail,
    GetContentRequest, MarkPushedRequest
)
from app.queue import task_queue
from app.adapters import AdapterFactory
from app.config import settings
from app.utils import normalize_bilibili_url, canonicalize_url

router = APIRouter()


def _extract_bearer(authorization: Optional[str]) -> Optional[str]:
    if not authorization:
        return None
    parts = authorization.split(" ", 1)
    if len(parts) == 2 and parts[0].lower() == "bearer":
        return parts[1].strip()
    return None


async def require_api_token(
    x_api_token: Optional[str] = Header(default=None, alias="X-API-Token"),
    authorization: Optional[str] = Header(default=None, alias="Authorization"),
):
    """M1：简单 Token 鉴权。

    - 当未设置 API_TOKEN 时：放行（便于本地开发）
    - 当设置了 API_TOKEN 时：要求 X-API-Token 或 Authorization: Bearer
    """
    expected = settings.api_token.get_secret_value() if settings.api_token else ""
    if not expected:
        return

    provided = x_api_token or _extract_bearer(authorization)
    if not provided or provided != expected:
        raise HTTPException(status_code=401, detail="Unauthorized")


@router.post("/shares", response_model=ShareResponse)
async def create_share(
    share: ShareRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    创建分享
    
    接收一个URL，识别平台，创建内容记录并加入解析队列
    """
    try:
        # 预处理：支持 BV/av/cv 直接输入
        raw_url = share.url
        url_for_detect = normalize_bilibili_url(raw_url)
        url_for_detect = canonicalize_url(url_for_detect)

        # 检测平台
        platform = AdapterFactory.detect_platform(url_for_detect)
        if not platform:
            raise HTTPException(status_code=400, detail="无法识别的平台URL")

        # 计算 canonical_url（用于去重）
        adapter = AdapterFactory.create(platform)
        canonical_url = await adapter.clean_url(url_for_detect)
        
        # 去重：platform + canonical_url
        result = await db.execute(
            select(Content).where(and_(Content.platform == platform, Content.canonical_url == canonical_url))
        )
        content = result.scalar_one_or_none()

        if content is None:
            # 创建内容记录
            content = Content(
                platform=platform,
                url=raw_url,
                canonical_url=canonical_url,
                clean_url=canonical_url,
                tags=share.tags,
                source=share.source,
                is_nsfw=share.is_nsfw,
                status=ContentStatus.UNPROCESSED,
            )
            db.add(content)
            await db.flush()

            # 首次入库才入队解析
            await task_queue.enqueue({
                'content_id': content.id,
                'action': 'parse'
            })

        # 记录来源（无论是否去重）
        db.add(
            ContentSource(
                content_id=content.id,
                source=share.source,
                tags_snapshot=share.tags,
                note=share.note,
                client_context=share.client_context,
            )
        )

        await db.commit()
        await db.refresh(content)

        with log_context(content_id=content.id):
            logger.info("创建分享成功")
        
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
    # 构建查询：解析完成（pulled）且未推送到目标平台
    # 兼容历史：曾经把 distributed 当状态用的旧数据，也视为解析完成
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
    
    记录推送历史（分发历史不作为全局 status 维护）
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
