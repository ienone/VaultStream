"""
FastAPI 路由
"""
from typing import List, Optional, Dict, Any
import os
import mimetypes
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException, Query, Header, Response, Request
from fastapi.responses import FileResponse, StreamingResponse
import httpx
from sqlalchemy import select, and_, or_, func, desc, text
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.concurrency import run_in_threadpool
from app.logging import logger, log_context

from app.database import get_db
from app.models import Content, ContentStatus, PushedRecord, Platform, ContentSource, Task, TaskStatus, DistributionRule, ReviewStatus, WeiboUser, SystemSetting
from app.schemas import (
    ShareRequest, ShareResponse, ContentDetail,
    GetContentRequest, MarkPushedRequest, ShareCard,
    ContentListResponse, ShareCardListResponse, TagStats, QueueStats, DashboardStats, ContentUpdate,
    ShareCardPreview, OptimizedMedia, DistributionRuleCreate, DistributionRuleUpdate, 
    DistributionRuleResponse, ReviewAction, BatchReviewRequest, PushedRecordResponse, WeiboUserResponse,
    SystemSettingResponse, SystemSettingUpdate
)
from app.storage import get_storage_backend, LocalStorageBackend
from app.queue import task_queue
from app.adapters import AdapterFactory
from app.config import settings
from app.utils import normalize_bilibili_url, canonicalize_url
from app.worker import worker

from app.repositories.content_repository import ContentRepository
from app.services.content_service import ContentService

router = APIRouter()

def _extract_bearer(authorization: Optional[str]) -> Optional[str]:
    if not authorization:
        return None
    parts = authorization.split(" ", 1)
    if len(parts) == 2 and parts[0].lower() == "bearer":
        return parts[1].strip()
    return None


async def require_api_token(
    x_api_token: str = Header(..., alias="X-API-Token"),
    authorization: Optional[str] = Header(default=None, alias="Authorization"),
):
    provided = x_api_token or _extract_bearer(authorization)
    expected = settings.api_token.get_secret_value() if settings.api_token else ""
    if not provided or provided != expected:
        raise HTTPException(status_code=401, detail="Invalid or missing API Token")

# --- 依赖项注入助手 ---
async def get_content_service(db: AsyncSession = Depends(get_db)) -> ContentService:
    return ContentService(db)

async def get_content_repo(db: AsyncSession = Depends(get_db)) -> ContentRepository:
    return ContentRepository(db)


@router.post("/shares", response_model=ShareResponse)
async def create_share(
    share: ShareRequest,
    service: ContentService = Depends(get_content_service),
    _: None = Depends(require_api_token),
):
    """创建分享 (重构版)"""
    try:
        content = await service.create_share(
            url=share.url,
            tags=share.tags,
            source_name=share.source,
            note=share.note,
            is_nsfw=share.is_nsfw,
            client_context=share.client_context
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


@router.post("/bot/get-content", response_model=List[ContentDetail])
async def get_content_for_bot(
    request: GetContentRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
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
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    供机器人调用：标记内容已推送（M4增强）
    
    记录推送历史，实现"同一目标推过不再推"逻辑
    """
    try:
        # 检查内容是否存在
        result = await db.execute(
            select(Content).where(Content.id == request.content_id)
        )
        content = result.scalar_one_or_none()
        
        if not content:
            raise HTTPException(status_code=404, detail="内容不存在")
        
        # M4: 检查是否已推送到该目标（使用 target_id 去重）
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
            # 如果已存在记录，更新 message_id（支持消息更新场景）
            if request.message_id:
                existing_record.message_id = request.message_id
                existing_record.push_status = "success"
                await db.commit()
                logger.info(f"更新推送记录: content_id={request.content_id}, target_id={request.target_id}")
            else:
                logger.info(f"推送记录已存在: content_id={request.content_id}, target_id={request.target_id}")
            
            return {"success": True, "message": "已更新", "record_id": existing_record.id}
        
        # 创建新推送记录
        pushed_record = PushedRecord(
            content_id=request.content_id,
            target_platform=request.target_platform,
            target_id=request.target_id,
            message_id=request.message_id,
            push_status="success"
        )
        db.add(pushed_record)

        await db.commit()
        
        logger.info(f"标记推送成功: content_id={request.content_id} -> {request.target_id}")
        
        return {"success": True, "message": "标记成功", "record_id": pushed_record.id}
        
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


@router.get("/cards", response_model=ShareCardListResponse)
async def list_share_cards(
    page: int = Query(1, ge=1),
    size: int = Query(20, ge=1, le=100),
    platform: Optional[Platform] = Query(None),
    status: Optional[ContentStatus] = Query(None),
    tag: Optional[str] = Query(None),
    author: Optional[str] = Query(None),
    start_date: Optional[datetime] = Query(None),
    end_date: Optional[datetime] = Query(None),
    q: Optional[str] = Query(None),
    repo: ContentRepository = Depends(get_content_repo),
    _: None = Depends(require_api_token),
):
    """轻量级分享卡片列表 (重构版)"""
    contents, total = await repo.list_contents(
        page=page, size=size, platform=platform, status=status, 
        tag=tag, author=author, start_date=start_date, end_date=end_date, q=q
    )

    items = []
    for c in contents:
        summary = (c.description or c.title or "")[:200]
        if len(c.description or c.title or "") > 200:
            summary += "..."

        items.append({
            "id": c.id,
            "platform": c.platform,
            "url": c.url,
            "clean_url": c.clean_url,
            "content_type": c.content_type,
            "title": c.title,
            "summary": summary,
            "description": c.description or c.title,
            "author_name": c.author_name,
            "author_id": c.author_id,
            "cover_url": c.cover_url,
            "cover_color": c.cover_color,
            "media_urls": [], 
            "tags": c.tags or [],
            "published_at": c.published_at,
            "view_count": c.view_count or 0,
            "like_count": c.like_count or 0,
            "collect_count": c.collect_count or 0,
            "share_count": c.share_count or 0,
            "comment_count": c.comment_count or 0,
        })

    return {
        "items": items,
        "total": total,
        "page": page,
        "size": size,
        "has_more": total > page * size
    }

    return {
        "items": items,
        "total": total,
        "page": page,
        "size": size,
        "has_more": total > page * size
    }


# --- M3: 私有存档查询与管理 API ---

@router.get("/contents", response_model=ContentListResponse)
async def list_contents(
    page: int = Query(1, ge=1),
    size: int = Query(20, ge=1, le=100),
    platform: Optional[Platform] = Query(None),
    status: Optional[ContentStatus] = Query(None),
    tag: Optional[str] = Query(None),
    author: Optional[str] = Query(None),
    start_date: Optional[datetime] = Query(None),
    end_date: Optional[datetime] = Query(None),
    q: Optional[str] = Query(None),
    is_nsfw: Optional[bool] = Query(None),
    repo: ContentRepository = Depends(get_content_repo),
    _: None = Depends(require_api_token),
):
    """完整内容列表查询 (重构版)"""
    items, total = await repo.list_contents(
        page=page, size=size, platform=platform, status=status,
        tag=tag, author=author, start_date=start_date, end_date=end_date, q=q, is_nsfw=is_nsfw
    )
    
    return {
        "items": items,
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
    """内容详情 (M3)"""
    result = await db.execute(select(Content).where(Content.id == content_id))
    content = result.scalar_one_or_none()
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")
    return content


from fastapi import BackgroundTasks

@router.post("/contents/{content_id}/re-parse")
async def re_parse_content(
    content_id: int,
    background_tasks: BackgroundTasks,
    repo: ContentRepository = Depends(get_content_repo),
    _: None = Depends(require_api_token),
):
    """强制重新解析内容 (异步重构版)"""
    content = await repo.get_by_id(content_id)
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")

    # 放入后台任务执行，立即返回
    background_tasks.add_task(worker.retry_parse, content_id, force=True)
    
    return {"status": "processing", "content_id": content_id, "message": "Re-parsing started in background"}


@router.patch("/contents/{content_id}", response_model=ContentDetail)
async def update_content(
    content_id: int,
    request: ContentUpdate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """修改内容 (M3)"""
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
    if request.is_nsfw is not None:
        content.is_nsfw = request.is_nsfw
    if request.status is not None:
        content.status = request.status
        
    await db.commit()
    await db.refresh(content)
    return content


@router.delete("/contents/{content_id}")
async def delete_content(
    content_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    删除内容
    
    注意：仅删除数据库记录，不删除存储的媒体文件
    """
    result = await db.execute(
        select(Content).where(Content.id == content_id)
    )
    content = result.scalar_one_or_none()
    
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")
    
    # 先删除关联的记录（避免外键约束错误）
    from app.models import ContentSource, PushedRecord
    
    # 删除 content_sources
    await db.execute(
        select(ContentSource).where(ContentSource.content_id == content_id)
    )
    await db.execute(
        ContentSource.__table__.delete().where(ContentSource.content_id == content_id)
    )
    
    # 删除 pushed_records
    await db.execute(
        PushedRecord.__table__.delete().where(PushedRecord.content_id == content_id)
    )
    
    # 最后删除 content
    await db.delete(content)
    await db.commit()
    
    logger.info(f"内容已删除: content_id={content_id}")
    return {"status": "deleted", "content_id": content_id}


@router.get("/tags", response_model=List[TagStats])
async def get_tags_list(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取所有标签列表及其使用次数 (M3)"""
    try:
        # 查询所有有标签的内容
        result = await db.execute(
            select(Content.tags).where(Content.tags.isnot(None))
        )
        all_tags_lists = result.scalars().all()
        
        counts = {}
        for tags in all_tags_lists:
            if isinstance(tags, list):
                for t in tags:
                    counts[t] = counts.get(t, 0) + 1
        
        # 转换为 Schema 格式并排序
        tag_stats = [
            {"name": name, "count": count} 
            for name, count in sorted(counts.items(), key=lambda x: x[1], reverse=True)
        ]
        return tag_stats
        
    except Exception as e:
        logger.exception("获取标签列表失败")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/dashboard/stats", response_model=DashboardStats)
async def get_dashboard_stats(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """仪表盘全局统计 (M3)"""
    # 平台分布统计
    platform_query = select(Content.platform, func.count()).group_by(Content.platform)
    platform_results = (await db.execute(platform_query)).all()
    # 注意：SQLAlchemy 返回的是元组，Platform 是枚举
    platform_counts = {str(p[0].value): p[1] for p in platform_results}
    
    # 最近 7 天增长趋势
    today = datetime.now().date()
    daily_growth = []
    for i in range(6, -1, -1):
        day = today - timedelta(days=i)
        day_start = datetime.combine(day, datetime.min.time())
        day_end = datetime.combine(day, datetime.max.time())
        
        count_q = select(func.count()).select_from(Content).where(
            and_(Content.created_at >= day_start, Content.created_at <= day_end)
        )
        day_count = (await db.execute(count_q)).scalar() or 0
        daily_growth.append({"date": day.isoformat(), "count": day_count})

    # 存储空间占用统计
    storage = get_storage_backend()
    usage = 0
    if isinstance(storage, LocalStorageBackend):
        root = storage.root_dir
        if os.path.exists(root):
            for dirpath, _, filenames in os.walk(root):
                for f in filenames:
                    usage += os.path.getsize(os.path.join(dirpath, f))
    
    return {
        "platform_counts": platform_counts,
        "daily_growth": daily_growth,
        "storage_usage_bytes": usage
    }


@router.get("/dashboard/queue", response_model=QueueStats)
async def get_dashboard_queue(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """任务队列状态统计 (M3)"""
    # 从 tasks 表获取待处理/进行中状态
    task_query = select(Task.status, func.count()).group_by(Task.status)
    task_results = (await db.execute(task_query)).all()
    task_stats = {str(r[0].value): r[1] for r in task_results}
    
    # 从 contents 表获取已归档统计
    archived_query = select(func.count()).select_from(Content).where(Content.status == ContentStatus.ARCHIVED)
    archived_count = (await db.execute(archived_query)).scalar() or 0
    
    total_tasks = sum(task_stats.values())
    
    return {
        "pending": task_stats.get("pending", 0),
        "processing": task_stats.get("running", 0),
        "failed": task_stats.get("failed", 0),
        "archived": archived_count,
        "total": total_tasks
    }


@router.get("/media/{key:path}")
async def proxy_media(
    key: str,
    storage: LocalStorageBackend = Depends(get_storage_backend),
):
    """
    媒体代理 API (M3)
    支持 Range 请求以加速播放视频预览。
    """
    if not isinstance(storage, LocalStorageBackend):
        raise HTTPException(status_code=400, detail="Only local storage proxy is supported")
        
    file_path = storage._full_path(key)
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="Media not found")
        
    mime_type, _ = mimetypes.guess_type(file_path)
    if not mime_type:
        mime_type = "application/octet-stream"
        
    # FileResponse 自动处理 Range 和文件流。
    return FileResponse(file_path, media_type=mime_type)


# ========== M4: 分享卡片预览 API ==========

@router.get("/contents/{content_id}/preview", response_model=ShareCardPreview)
async def get_content_preview(
    content_id: int,
    db: AsyncSession = Depends(get_db),
    storage: LocalStorageBackend = Depends(get_storage_backend),
    _: None = Depends(require_api_token),
):
    """
    获取内容的分享卡片预览（M4）
    
    严格剥离敏感信息，仅返回合规字段和优化媒体资源
    """
    result = await db.execute(select(Content).where(Content.id == content_id))
    content = result.scalar_one_or_none()
    
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")
    
    # 构建优化媒体列表
    optimized_media = []
    base_url = settings.base_url or "http://localhost:8000"
    
    # 处理媒体URL（如果已下载到本地）
    if content.media_urls:
        for media_url in content.media_urls:
            # 检查是否是本地存储的媒体
            if media_url.startswith("local://"):
                key = media_url.replace("local://", "")
                proxy_url = f"{base_url}/api/v1/media/{key}"
                
                # 尝试获取媒体信息
                file_path = storage._full_path(key)
                size_bytes = os.path.getsize(file_path) if os.path.exists(file_path) else None
                
                # 判断媒体类型
                mime_type, _ = mimetypes.guess_type(key)
                media_type = "image" if mime_type and mime_type.startswith("image/") else "video"
                
                optimized_media.append(OptimizedMedia(
                    type=media_type,
                    url=proxy_url,
                    size_bytes=size_bytes
                ))
            else:
                # 外部URL（未下载）
                optimized_media.append(OptimizedMedia(
                    type="image",  # 默认假定为图片
                    url=media_url
                ))
    
    # 生成摘要（从description截取前200字符）
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


# ========== M4: 分发规则 CRUD API ==========

@router.post("/distribution-rules", response_model=DistributionRuleResponse)
async def create_distribution_rule(
    rule: DistributionRuleCreate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """创建分发规则"""
    # 检查名称是否重复
    result = await db.execute(
        select(DistributionRule).where(DistributionRule.name == rule.name)
    )
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Rule name already exists")
    
    db_rule = DistributionRule(**rule.model_dump())
    db.add(db_rule)
    await db.commit()
    await db.refresh(db_rule)
    
    logger.info(f"分发规则已创建: {db_rule.name} (ID: {db_rule.id})")
    return db_rule


@router.get("/distribution-rules", response_model=List[DistributionRuleResponse])
async def list_distribution_rules(
    enabled: Optional[bool] = None,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取所有分发规则"""
    query = select(DistributionRule).order_by(desc(DistributionRule.priority), DistributionRule.id)
    
    if enabled is not None:
        query = query.where(DistributionRule.enabled == enabled)
    
    result = await db.execute(query)
    rules = result.scalars().all()
    return rules


@router.get("/distribution-rules/{rule_id}", response_model=DistributionRuleResponse)
async def get_distribution_rule(
    rule_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取单个分发规则"""
    result = await db.execute(
        select(DistributionRule).where(DistributionRule.id == rule_id)
    )
    rule = result.scalar_one_or_none()
    
    if not rule:
        raise HTTPException(status_code=404, detail="Distribution rule not found")
    
    return rule


@router.patch("/distribution-rules/{rule_id}", response_model=DistributionRuleResponse)
async def update_distribution_rule(
    rule_id: int,
    rule_update: DistributionRuleUpdate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """更新分发规则"""
    result = await db.execute(
        select(DistributionRule).where(DistributionRule.id == rule_id)
    )
    db_rule = result.scalar_one_or_none()
    
    if not db_rule:
        raise HTTPException(status_code=404, detail="Distribution rule not found")
    
    # 更新字段
    update_data = rule_update.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(db_rule, key, value)
    
    await db.commit()
    await db.refresh(db_rule)
    
    logger.info(f"分发规则已更新: {db_rule.name} (ID: {db_rule.id})")
    return db_rule


@router.delete("/distribution-rules/{rule_id}")
async def delete_distribution_rule(
    rule_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """删除分发规则"""
    result = await db.execute(
        select(DistributionRule).where(DistributionRule.id == rule_id)
    )
    db_rule = result.scalar_one_or_none()
    
    if not db_rule:
        raise HTTPException(status_code=404, detail="Distribution rule not found")
    
    await db.delete(db_rule)
    await db.commit()
    
    logger.info(f"分发规则已删除: {db_rule.name} (ID: {rule_id})")
    return {"status": "deleted", "id": rule_id}


# ========== M4: 审批流 API ==========

@router.post("/contents/{content_id}/review")
async def review_content(
    content_id: int,
    action: ReviewAction,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """审批单个内容"""
    result = await db.execute(select(Content).where(Content.id == content_id))
    content = result.scalar_one_or_none()
    
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")
    
    if action.action not in ["approve", "reject"]:
        raise HTTPException(status_code=400, detail="Invalid action")
    
    # 更新审批状态
    content.review_status = ReviewStatus.APPROVED if action.action == "approve" else ReviewStatus.REJECTED
    content.reviewed_at = datetime.utcnow()
    content.reviewed_by = action.reviewed_by
    content.review_note = action.note
    
    await db.commit()
    await db.refresh(content)
    
    logger.info(f"内容审批完成: content_id={content_id}, action={action.action}, by={action.reviewed_by}")
    
    return {
        "id": content.id,
        "review_status": content.review_status,
        "reviewed_at": content.reviewed_at
    }


@router.post("/contents/batch-review")
async def batch_review_contents(
    request: BatchReviewRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """批量审批内容"""
    if request.action not in ["approve", "reject"]:
        raise HTTPException(status_code=400, detail="Invalid action")
    
    review_status = ReviewStatus.APPROVED if request.action == "approve" else ReviewStatus.REJECTED
    
    # 批量更新
    result = await db.execute(
        select(Content).where(Content.id.in_(request.content_ids))
    )
    contents = result.scalars().all()
    
    if not contents:
        raise HTTPException(status_code=404, detail="No contents found")
    
    updated_count = 0
    for content in contents:
        content.review_status = review_status
        content.reviewed_at = datetime.utcnow()
        content.reviewed_by = request.reviewed_by
        content.review_note = request.note
        updated_count += 1
    
    await db.commit()
    
    logger.info(f"批量审批完成: {updated_count} 条内容, action={request.action}")
    
    return {
        "updated": updated_count,
        "action": request.action,
        "content_ids": request.content_ids
    }


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
    
    # 计算总数
    count_result = await db.execute(
        select(func.count()).select_from(query.subquery())
    )
    total = count_result.scalar() or 0
    
    # 分页查询
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


# ========== M4: 推送记录查询 API ==========

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


@router.get("/proxy/image")
async def proxy_image(url: str = Query(..., description="要代理的图片 URL")):
    """通用图片代理，用于解决跨域、Referer 校验或网络瓶颈（如 Twitter/B站）"""
    async def stream_image():
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
        }
        # 针对 B 站图片添加 Referer
        if "hdslb.com" in url or "bilibili" in url:
            headers["Referer"] = "https://www.bilibili.com/"
        elif "sinaimg.cn" in url or "weibocdn.com" in url:
            headers["Referer"] = "https://weibo.com/"
        
        # 使用配置的代理
        proxy = settings.http_proxy or settings.https_proxy
        
        async with httpx.AsyncClient(proxy=proxy, timeout=10.0) as client:
            try:
                async with client.stream("GET", url, headers=headers, follow_redirects=True) as resp:
                    if resp.status_code != 200:
                         logger.error(f"Image proxy upstream error {resp.status_code} for {url}")
                         # 抛出异常以中断连接，避免返回 200 OK 空响应
                         raise Exception(f"Upstream error {resp.status_code}")
                    
                    async for chunk in resp.aiter_bytes():
                        yield chunk
            except Exception as e:
                logger.error(f"Image proxy error for {url}: {e}")

    return StreamingResponse(stream_image(), media_type="image/jpeg")


# ========== Weibo Specific API ==========

@router.post("/weibo/users/{uid}/archive", response_model=WeiboUserResponse)
async def archive_weibo_user(
    uid: str,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    存档微博用户数据
    
    调用微博适配器获取用户详细信息并存入数据库
    """
    try:
        # 使用 AdapterFactory 创建 adapter
        adapter = AdapterFactory.create(Platform.WEIBO)
        
        # 确保 adapter 支持 fetch_user_profile
        if not hasattr(adapter, 'fetch_user_profile'):
             raise HTTPException(status_code=500, detail="Adapter does not support user fetching")
        
        # 在线程池中运行同步的 request 调用
        user_data = await run_in_threadpool(adapter.fetch_user_profile, uid)
        
        # 检查用户是否存在
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
            # 更新现有用户
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


# ========== System Settings API ==========

@router.get("/settings", response_model=List[SystemSettingResponse])
async def list_settings(
    category: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取系统设置列表"""
    query = select(SystemSetting)
    if category:
        query = query.where(SystemSetting.category == category)
    
    result = await db.execute(query)
    settings_list = result.scalars().all()
    return settings_list


@router.get("/settings/{key}", response_model=SystemSettingResponse)
async def get_setting(
    key: str,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取单个设置"""
    result = await db.execute(select(SystemSetting).where(SystemSetting.key == key))
    setting = result.scalar_one_or_none()
    if not setting:
        raise HTTPException(status_code=404, detail="Setting not found")
    return setting


@router.put("/settings/{key}", response_model=SystemSettingResponse)
async def update_setting(
    key: str,
    update: SystemSettingUpdate,
    category: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """创建或更新设置"""
    result = await db.execute(select(SystemSetting).where(SystemSetting.key == key))
    setting = result.scalar_one_or_none()
    
    if setting:
        setting.value = update.value
        if update.description:
            setting.description = update.description
        if category:
            setting.category = category
    else:
        setting = SystemSetting(
            key=key,
            value=update.value,
            category=category or "general",
            description=update.description
        )
        db.add(setting)
    
    await db.commit()
    await db.refresh(setting)
    return setting


@router.delete("/settings/{key}")
async def delete_setting(
    key: str,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """删除设置"""
    result = await db.execute(select(SystemSetting).where(SystemSetting.key == key))
    setting = result.scalar_one_or_none()
    if not setting:
        raise HTTPException(status_code=404, detail="Setting not found")
    
    await db.delete(setting)
    await db.commit()
    return {"status": "deleted", "key": key}

