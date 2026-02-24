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
from app.models import SystemSetting, Content
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
    queue_ok = await task_queue.ping()
    db_ok = await db_ping()
    queue_size = await task_queue.get_queue_size()
    
    status = "ok" if (queue_ok and db_ok) else "degraded"
    
    return {
        "status": status,
        "queue_size": queue_size,
        "components": {
            "db": "ok" if db_ok else "error",
            "queue": "ok" if queue_ok else "error"
        }
    }

@router.get("/init-status")
async def get_init_status(
    db: AsyncSession = Depends(get_db)
):
    """获取初始化状态（无需 Token）"""
    from app.models import BotConfig, SystemSetting
    
    # 检查数据库中是否已配置核心 AI Key (忽略 .env 环境变量以便强制在前端走一遍引导流程)
    setting_result = await db.execute(
        select(SystemSetting.value).where(SystemSetting.key == "text_llm_api_key")
    )
    llm_key_in_db = setting_result.scalar_one_or_none()
    
    # 检查是否有 Bot 配置
    bot_result = await db.execute(select(func.count()).select_from(BotConfig))
    bot_count = bot_result.scalar() or 0
    
    return {
        "needs_setup": not bool(llm_key_in_db),
        "has_bot": bot_count > 0,
        "version": "0.1.0"
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
    from app.services.dashboard_service import build_parse_stats, build_distribution_stats

    parse_stats = await build_parse_stats(db)
    distribution_stats, _ = await build_distribution_stats(db)

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
