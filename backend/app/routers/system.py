"""
功能描述：系统管理 API
包含：系统设置、仪表盘统计、健康检查
调用方式：需要 API Token (Health Check 除外)
"""
from typing import List, Optional, Dict
from datetime import datetime, timedelta
import os
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, and_, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db, db_ping
from app.models import SystemSetting, Content, ContentStatus, ContentQueueItem, QueueItemStatus
from app.schemas import (
    SystemSettingResponse, SystemSettingUpdate, DashboardStats, 
    QueueStats, TagStats, QueueOverviewStats, DistributionStatusStats
)
from app.core.logging import logger
from app.core.dependencies import require_api_token
from app.core.storage import get_storage_backend, LocalStorageBackend
from app.core.queue import task_queue

router = APIRouter()

@router.get("/health")
async def health_check():
    """健康检查"""
    redis_ok = await task_queue.ping()
    db_ok = await db_ping()
    queue_size = await task_queue.get_queue_size()
    
    status = "ok" if (redis_ok and db_ok) else "degraded"
    
    return {
        "status": status,
        "queue_size": queue_size,
        "components": {
            "db": "ok" if db_ok else "error",
            "redis": "ok" if redis_ok else "error"
        }
    }

@router.get("/dashboard/stats", response_model=DashboardStats)
async def get_dashboard_stats(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """仪表盘全局统计"""
    platform_query = select(Content.platform, func.count()).group_by(Content.platform)
    platform_results = (await db.execute(platform_query)).all()
    platform_counts = {str(p[0].value): p[1] for p in platform_results}
    
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

@router.get("/dashboard/queue", response_model=QueueOverviewStats)
async def get_dashboard_queue(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """看板状态统计：顶层解析状态 + 解析成功下的分发状态。"""
    parse_stats = {
        "unprocessed": 0,
        "processing": 0,
        "parse_success": 0,
        "parse_failed": 0,
        "total": 0,
    }

    status_query = select(Content.status, func.count(Content.id)).group_by(Content.status)
    for status, count in (await db.execute(status_query)).all():
        count_int = int(count or 0)
        parse_stats["total"] += count_int
        if status == ContentStatus.UNPROCESSED:
            parse_stats["unprocessed"] += count_int
        elif status == ContentStatus.PROCESSING:
            parse_stats["processing"] += count_int
        elif status == ContentStatus.PARSE_SUCCESS:
            parse_stats["parse_success"] += count_int
        elif status == ContentStatus.PARSE_FAILED:
            parse_stats["parse_failed"] += count_int

    distribution_stats = {
        "will_push": 0,
        "filtered": 0,
        "pending_review": 0,
        "pushed": 0,
        "total": 0,
    }
    queue_query = (
        select(
            ContentQueueItem.status,
            ContentQueueItem.needs_approval,
            ContentQueueItem.approved_at,
            func.count(ContentQueueItem.id),
        )
        .join(Content, Content.id == ContentQueueItem.content_id)
        .where(Content.status == ContentStatus.PARSE_SUCCESS)
        .group_by(
            ContentQueueItem.status,
            ContentQueueItem.needs_approval,
            ContentQueueItem.approved_at,
        )
    )
    for status, needs_approval, approved_at, count in (await db.execute(queue_query)).all():
        count_int = int(count or 0)
        if status == QueueItemStatus.SUCCESS:
            bucket = "pushed"
        elif status in (QueueItemStatus.SKIPPED, QueueItemStatus.CANCELED):
            bucket = "filtered"
        elif status == QueueItemStatus.PENDING and bool(needs_approval) and approved_at is None:
            bucket = "pending_review"
        else:
            bucket = "will_push"

        distribution_stats[bucket] += count_int
        distribution_stats["total"] += count_int

    return {
        "parse": QueueStats(**parse_stats),
        "distribution": DistributionStatusStats(**distribution_stats),
    }

@router.get("/tags", response_model=List[TagStats])
async def get_tags_list(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取所有标签列表及其使用次数"""
    try:
        result = await db.execute(select(Content.tags).where(Content.tags.isnot(None)))
        all_tags_lists = result.scalars().all()
        
        counts = {}
        for tags in all_tags_lists:
            if isinstance(tags, list):
                for t in tags:
                    counts[t] = counts.get(t, 0) + 1
        
        tag_stats = [
            {"name": name, "count": count} 
            for name, count in sorted(counts.items(), key=lambda x: x[1], reverse=True)
        ]
        return tag_stats
    except Exception as e:
        logger.exception("获取标签列表失败")
        raise HTTPException(status_code=500, detail=str(e))

# --- System Settings ---

@router.get("/settings", response_model=List[SystemSettingResponse])
async def list_settings(
    category: Optional[str] = None,
    _: None = Depends(require_api_token),
):
    """获取系统设置列表"""
    from app.services.settings_service import list_settings_values
    return await list_settings_values(category)

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
    _: None = Depends(require_api_token),
):
    """创建或更新设置"""
    from app.services.settings_service import set_setting_value
    return await set_setting_value(key, update.value, category, update.description)

@router.delete("/settings/{key}")
async def delete_setting(
    key: str,
    _: None = Depends(require_api_token),
):
    """删除设置"""
    from app.services.settings_service import delete_setting_value
    success = await delete_setting_value(key)
    if not success:
        raise HTTPException(status_code=404, detail="Setting not found")
    
    return {"status": "deleted", "key": key}
