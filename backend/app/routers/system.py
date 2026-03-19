"""
功能描述：系统管理 API
包含：系统设置、仪表盘统计、健康检查
调用方式：需要 API Token (Health Check 除外)
"""
from typing import List, Optional, Dict, Any
from datetime import datetime, timedelta
import asyncio
import os
import time
from fastapi import APIRouter, Depends, HTTPException, Query, Request, Body
from sqlalchemy import select, and_, func, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db, db_ping
from app.models import SystemSetting, Content, DiscoveryState
from app.schemas import (
    SystemSettingResponse, SystemSettingUpdate, DashboardStats, 
    QueueStats, TagStats, QueueOverviewStats, DistributionStatusStats,
    FavoritesSyncTriggerRequest,
)
from app.core.logging import logger
from app.core.dependencies import require_api_token
from app.core.api_errors import build_error_payload
from app.adapters.favorites.errors import FavoritesFetchError
from app.adapters.storage import get_storage_backend, LocalStorageBackend
from app.core.queue import task_queue
from app.utils.sensitive_display import as_configured_placeholder, is_sensitive_setting_key

router = APIRouter()

_storage_usage_cache: dict = {"value": 0, "expires_at": 0.0}
_STORAGE_CACHE_TTL = 300  # 5 minutes


def _get_cached_storage_usage() -> int:
    now = time.monotonic()
    if now < _storage_usage_cache["expires_at"]:
        return _storage_usage_cache["value"]

    storage = get_storage_backend()
    usage = 0
    if isinstance(storage, LocalStorageBackend):
        root = storage.root_dir
        if os.path.exists(root):
            for dirpath, _, filenames in os.walk(root):
                for f in filenames:
                    try:
                        usage += os.path.getsize(os.path.join(dirpath, f))
                    except OSError:
                        pass

    _storage_usage_cache["value"] = usage
    _storage_usage_cache["expires_at"] = now + _STORAGE_CACHE_TTL
    return usage


def _serialize_setting_for_response(setting: SystemSetting) -> dict:
    """Serialize setting rows with sensitive-value masking for API responses."""
    value = setting.value
    if is_sensitive_setting_key(setting.key):
        value = as_configured_placeholder(setting.value, source="db") or ""
    return {
        "key": setting.key,
        "value": value,
        "category": setting.category,
        "description": setting.description,
        "updated_at": setting.updated_at,
    }

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
    _library_content = or_(
        Content.discovery_state.is_(None),
        Content.discovery_state == DiscoveryState.PROMOTED,
    )

    platform_query = (
        select(Content.platform, func.count())
        .where(_library_content)
        .group_by(Content.platform)
    )
    platform_results = (await db.execute(platform_query)).all()
    platform_counts = {str(p[0].value): p[1] for p in platform_results}
    
    today = datetime.now().date()
    daily_growth = []
    for i in range(6, -1, -1):
        day = today - timedelta(days=i)
        day_start = datetime.combine(day, datetime.min.time())
        day_end = datetime.combine(day, datetime.max.time())
        count_q = select(func.count()).select_from(Content).where(
            and_(
                Content.created_at >= day_start,
                Content.created_at <= day_end,
                _library_content,
            )
        )
        day_count = (await db.execute(count_q)).scalar() or 0
        daily_growth.append({"date": day.isoformat(), "count": day_count})

    usage = _get_cached_storage_usage()
    
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
        raise HTTPException(
            status_code=500,
            detail=build_error_payload(
                message="获取标签列表失败",
                code="tags_query_failed",
                hint="请稍后重试，若持续失败请检查后端日志",
            ),
        )

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
        raise HTTPException(
            status_code=404,
            detail=build_error_payload(
                message="Setting not found",
                code="setting_not_found",
            ),
        )
    return _serialize_setting_for_response(setting)

@router.put("/settings/{key}", response_model=SystemSettingResponse)
async def update_setting(
    key: str,
    update: SystemSettingUpdate,
    category: Optional[str] = Query(None),
    _: None = Depends(require_api_token),
):
    """创建或更新设置"""
    from app.services.settings_service import set_setting_value
    setting = await set_setting_value(key, update.value, category, update.description)
    return _serialize_setting_for_response(setting)

@router.delete("/settings/{key}")
async def delete_setting(
    key: str,
    _: None = Depends(require_api_token),
):
    """删除设置"""
    from app.services.settings_service import delete_setting_value
    success = await delete_setting_value(key)
    if not success:
        raise HTTPException(
            status_code=404,
            detail=build_error_payload(
                message="Setting not found",
                code="setting_not_found",
            ),
        )
    
    return {"status": "deleted", "key": key}


@router.get("/favorites-sync/status")
async def get_favorites_sync_status(
    request: Request,
    _: None = Depends(require_api_token),
):
    """Get favorites sync runtime/settings status for frontend panel."""
    from app.services.settings_service import get_setting_value
    from app.tasks.favorites_sync import FavoritesSyncTask

    sync_task = getattr(request.app.state, "favorites_sync_task", None)
    if sync_task is None:
        sync_task = FavoritesSyncTask()

    interval = int(
        await get_setting_value(
            "favorites_sync_interval_minutes",
            FavoritesSyncTask._DEFAULT_INTERVAL_MINUTES,
        )
    )
    max_items = int(
        await get_setting_value(
            "favorites_sync_max_items",
            FavoritesSyncTask._DEFAULT_MAX_ITEMS,
        )
    )
    enabled_platforms = await sync_task.load_enabled_platforms()
    last_sync_at = await get_setting_value("favorites_sync_last_sync_at")

    platforms: list[dict[str, Any]] = []
    for platform in sync_task.get_supported_platforms():
        fetcher_cls = sync_task.get_fetcher_cls(platform)
        if fetcher_cls is None:
            continue

        authenticated = False
        available = True
        error: Optional[str] = None
        status_error: Optional[dict[str, Any]] = None
        should_probe_auth = platform in enabled_platforms
        if should_probe_auth:
            try:
                authenticated = await fetcher_cls().check_auth()
            except ImportError as e:
                available = False
                error = str(e)
                status_error = build_error_payload(
                    message=str(e),
                    code="dependency_missing",
                    hint="依赖缺失，请检查后端运行环境",
                    request_id=getattr(request.state, "request_id", None),
                )
                logger.warning("[favorites status] check_auth import error for {}: {}", platform, e)
            except FavoritesFetchError as e:
                available = e.code != "cli_unavailable"
                error = e.message
                status_error = {
                    "detail": e.message,
                    **e.as_dict(),
                    "request_id": getattr(request.state, "request_id", None),
                }
                logger.warning(
                    "[favorites status] structured check_auth failure for {}: code={} message={}",
                    platform,
                    e.code,
                    e.message,
                )
            except Exception as e:
                available = False
                error = str(e)
                status_error = build_error_payload(
                    message=str(e),
                    code="auth_check_failed",
                    hint="认证检查失败，请稍后重试",
                    request_id=getattr(request.state, "request_id", None),
                )
                logger.exception("[favorites status] check_auth failed for {}", platform)

        rate = float(
            await get_setting_value(
                f"favorites_sync_rate_{platform}",
                sync_task.default_rate_for(platform),
            )
        )
        last_result = await get_setting_value(f"favorites_sync_last_result_{platform}")

        platforms.append(
            {
                "platform": platform,
                "enabled": platform in enabled_platforms,
                "available": available,
                "authenticated": authenticated,
                "rate_per_minute": rate,
                "last_result": last_result,
                "error": error,
                "status_error": status_error,
            }
        )

    return {
        "running": sync_task.is_running(),
        "interval_minutes": interval,
        "max_items": max_items,
        "enabled_platforms": enabled_platforms,
        "last_sync_at": last_sync_at,
        "platforms": platforms,
    }


@router.post("/favorites-sync/sync", status_code=202)
async def trigger_favorites_sync(
    request: Request,
    body: FavoritesSyncTriggerRequest | None = Body(default=None),
    _: None = Depends(require_api_token),
):
    """Trigger one round of favorites sync (all platforms or single platform)."""
    sync_task = getattr(request.app.state, "favorites_sync_task", None)
    if sync_task is None:
        raise HTTPException(
            status_code=503,
            detail=build_error_payload(
                message="Favorites sync task is not running",
                code="favorites_task_unavailable",
                hint="请确认后端任务已启动后重试",
                request_id=getattr(request.state, "request_id", None),
            ),
        )

    platform = ((body.platform if body else "") or "").strip().lower()
    if platform:
        if platform not in sync_task.get_supported_platforms():
            raise HTTPException(
                status_code=400,
                detail=build_error_payload(
                    message=f"Unknown platform: {platform}",
                    code="unsupported_platform",
                    hint="仅支持 zhihu / xiaohongshu / twitter",
                    request_id=getattr(request.state, "request_id", None),
                ),
            )
        asyncio.create_task(sync_task.sync_platform_by_name(platform))
        return {"status": "accepted", "platform": platform}

    asyncio.create_task(sync_task.sync_all_platforms_once())
    return {"status": "accepted", "platform": "all"}
