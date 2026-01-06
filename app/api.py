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
    GetContentRequest, MarkPushedRequest, ShareCard
)
from app.queue import task_queue
from app.adapters import AdapterFactory
from app.config import settings
from app.utils import normalize_bilibili_url, canonicalize_url
from app.worker import worker

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

        is_new = False
        if content is None:
            # 创建内容记录（存档为主）
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
            is_new = True

        else:
            # 存档优先：合并 tags、更新来源信息并始终写入 ContentSource
            try:
                existing_tags = set(content.tags or [])
                incoming_tags = set(share.tags or [])
                merged = list(existing_tags.union(incoming_tags))
                content.tags = merged
            except Exception:
                # 若 tags 结构异常，回退为传入 tags
                content.tags = share.tags or []

            if share.source:
                content.source = share.source

            # 不再由分享触发自动重试：仅记录来源与标签，手动或后台重试由专门接口触发

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

        # 确保在事务提交并刷新内容记录后再入队，避免 worker 在未提交时读取不到记录导致竞态
        if is_new:
            await task_queue.enqueue({
                'content_id': content.id,
                'action': 'parse'
            })

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


@router.post("/contents/{content_id}/retry")
async def retry_content(
    content_id: int,
    max_retries: int = 3,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """手动触发对指定内容的重试解析。

    - `max_retries` 控制最大尝试次数（包含首次尝试）。
    - 该接口不会重置 content 的其他字段，仅调用后台重试逻辑。
    """
    try:
        result = await db.execute(
            select(Content).where(Content.id == content_id)
        )
        content = result.scalar_one_or_none()

        if not content:
            raise HTTPException(status_code=404, detail="内容不存在")

        ok = await worker.retry_parse(content_id, max_retries=max_retries)

        if not ok:
            # 重试达上限或内部错误，返回 500 并保留失败信息在内容记录中
            raise HTTPException(status_code=500, detail="重试失败或达到最大重试次数")

        # 刷新并返回最新状态
        await db.refresh(content)
        return {"success": True, "content_id": content_id, "status": content.status}

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"重试接口失败: {e}")
        raise HTTPException(status_code=500, detail=str(e))


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
    try:
        query = select(Content)
        
        # 添加过滤条件
        conditions = []
        if status:
            conditions.append(Content.status == status)
        if platform:
            conditions.append(Content.platform == platform)
        # 安全处理tag查询：忽略空字符串
        if tag and isinstance(tag, str) and tag.strip():
            conditions.append(Content.tags.contains([tag.strip()]))
        
        if conditions:
            query = query.where(and_(*conditions))
        
        query = query.order_by(Content.created_at.desc()).limit(limit).offset(offset)
        
        result = await db.execute(query)
        contents = result.scalars().all()
        
        return [ContentDetail.model_validate(c) for c in contents]
    except Exception as e:
        logger.exception("列出内容失败")
        raise HTTPException(
            status_code=500,
            detail=f"查询失败: {str(e)[:200]}"
        )


@router.post("/bot/get-content", response_model=List[ContentDetail])
async def get_content_for_bot(
    request: GetContentRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    供机器人调用：获取待分发的内容
    
    返回未推送到指定平台的内容
    支持按标签和平台筛选
    返回完整的 ContentDetail（包含 raw_metadata）以便 bot 能访问媒体存档
    """
    try:
        # 构建查询：解析完成（pulled）且未推送到目标平台
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
        if request.tag and isinstance(request.tag, str) and request.tag.strip():
            tag_value = request.tag.strip()
            query = query.where(Content.tags.contains([tag_value]))
        
        # 按平台过滤（新增）
        if hasattr(request, 'platform') and request.platform:
            try:
                platform_enum = Platform(request.platform)
                query = query.where(Content.platform == platform_enum)
            except ValueError:
                raise HTTPException(status_code=400, detail=f"无效的平台: {request.platform}")
        
        query = query.order_by(Content.created_at.desc()).limit(request.limit)
        
        result = await db.execute(query)
        contents = result.scalars().all()
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("查询待推送内容失败")
        raise HTTPException(
            status_code=500, 
            detail=f"查询失败: {str(e)[:200]}"
        )

    # Bot 内部调用：返回完整 ContentDetail（包含 raw_metadata）
    logger.info(f"Bot 获取内容成功: platform={request.platform}, tag={request.tag}, count={len(contents)}")
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


@router.get("/tags")
async def get_tags(db: AsyncSession = Depends(get_db)):
    """获取所有标签及其使用次数"""
    try:
        from sqlalchemy import func, distinct
        from sqlalchemy.dialects.postgresql import JSONB
        
        # 查询所有已解析的内容的标签
        result = await db.execute(
            select(Content.tags).where(
                and_(
                    Content.status == ContentStatus.PULLED,
                    Content.tags.isnot(None)
                )
            )
        )
        contents = result.scalars().all()
        
        # 统计标签出现次数
        tag_counts = {}
        for tags in contents:
            if tags and isinstance(tags, list):
                for tag in tags:
                    if tag and isinstance(tag, str):
                        tag_counts[tag] = tag_counts.get(tag, 0) + 1
        
        return tag_counts
        
    except Exception as e:
        logger.exception("获取标签列表失败")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/media/{key:path}")
async def get_media(key: str):
    """
    代理本地存储的媒体文件
    仅在使用本地存储模式时有效
    """
    from fastapi.responses import Response
    from app.storage import get_storage_backend, LocalStorageBackend
    import mimetypes
    
    try:
        storage = get_storage_backend()
        
        # 仅本地存储需要代理
        if not isinstance(storage, LocalStorageBackend):
            raise HTTPException(404, "Not a local storage endpoint")
        
        # 读取文件
        file_path = storage._full_path(key)
        import os
        if not os.path.exists(file_path):
            raise HTTPException(404, "Media not found")
        
        # 读取文件内容
        with open(file_path, 'rb') as f:
            data = f.read()
        
        # 根据扩展名推断 Content-Type
        content_type = mimetypes.guess_type(key)[0] or "application/octet-stream"
        
        return Response(content=data, media_type=content_type)
        
    except HTTPException:
        raise
    except Exception as e:
        logger.exception(f"获取媒体文件失败: {key}")
        raise HTTPException(status_code=500, detail=str(e))
