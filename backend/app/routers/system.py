"""
功能描述：系统管理 API
包含：系统设置、仪表盘统计、健康检查
调用方式：需要 API Token (Health Check 除外)
"""
from typing import List, Optional
from datetime import datetime, timedelta
import os
import time
import httpx
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Request, Body, Response
from pydantic import BaseModel
from sqlalchemy import select, and_, func, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db, get_database_health
from app.core.db_adapter import AsyncSessionLocal
from app.models import (
    Content,
    DiscoveryState,
    SystemSetting,
)
from app.schemas import (
    AIConnectivityTestResponse,
    AIModelDiscoveryResponse,
    SystemSettingDeleteResponse,
    SystemSettingResponse, SystemSettingUpdate, DashboardStats, 
    QueueStats, TagStats, QueueOverviewStats, DistributionStatusStats,
    FavoritesSyncAcceptedResponse,
    FavoritesSyncStatusResponse,
    FavoritesSyncItemRetryResponse,
    FavoritesSyncItemsRetryResponse,
    FavoritesSyncItemRetryRequest,
    FavoritesSyncItemsRetryRequest,
    FavoritesSyncPreviewRequest, FavoritesSyncPreviewResponse,
    FavoritesSyncTriggerRequest, BackgroundTaskDiagnosticsResponse,
    BackgroundTaskRunResponse,
    PlatformParseTestResponse,
)
from app.core.logging import logger
from app.core.dependencies import require_api_token
from app.core.api_errors import build_error_payload
from app.adapters.storage import get_storage_backend, LocalStorageBackend
from app.core.queue import task_queue
from app.services.ai_diagnostics import (
    AIDiagnosticsService,
    get_ai_diagnostics_service,
)
from app.services.favorites_sync_service import (
    FavoritesSyncService,
    FavoritesSyncServiceError,
    get_favorites_sync_service,
)
from app.services.platform_health_service import (
    PlatformHealthService,
    get_platform_health_service,
)
from app.services.system_diagnostics_service import (
    SystemDiagnosticsService,
    get_system_diagnostics_service,
)
from app.utils.sensitive_display import as_configured_placeholder, is_sensitive_setting_key

router = APIRouter()

_storage_usage_cache: dict = {"value": 0, "expires_at": 0.0}
_STORAGE_CACHE_TTL = 300  # 5 minutes


class AIConnectivityTestRequest(BaseModel):
    target: str


class AIModelDiscoveryRequest(BaseModel):
    target: str


class PlatformParseTestRequest(BaseModel):
    platform: str
    url: str


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
async def health_check(
    diagnostics: SystemDiagnosticsService = Depends(
        get_system_diagnostics_service
    ),
):
    """健康检查"""
    queue_ok = await task_queue.ping()
    db_health = await get_database_health()
    db_ok = db_health["status"] == "ok"
    fts_ok = db_health.get("fts", {}).get("available", False)
    queue_size = await task_queue.get_queue_size()
    async with AsyncSessionLocal() as db:
        background = await diagnostics.build_background_summary(db)
        providers = await diagnostics.build_provider_diagnostics(db)
    
    status = "ok" if (queue_ok and db_ok and fts_ok) else "degraded"
    
    return {
        "status": status,
        "queue_size": queue_size,
        "components": {
            "db": "ok" if db_ok else "error",
            "queue": "ok" if queue_ok else "error",
            "fts": "ok" if fts_ok else db_health.get("fts", {}).get("status", "error"),
            "workers": "ok",
            "providers": "ok",
        },
        "checks": {
            "database": db_health,
            "workers": {
                "parse_worker_count": settings.parse_worker_count,
                "queue_worker_count": settings.queue_worker_count,
            },
            "providers": providers,
            "background_tasks": background,
        },
    }

@router.get("/init-status")
async def get_init_status(
    db: AsyncSession = Depends(get_db)
):
    """获取初始化状态（无需 Token）"""
    from app.models import BotConfig, SystemSetting
    
    # 引导完成状态与模型配置解耦：LLM 功能是可选项，不能再用 API Key 判断。
    setting_result = await db.execute(
        select(SystemSetting.value).where(SystemSetting.key == "onboarding_completed")
    )
    onboarding_completed = str(setting_result.scalar_one_or_none() or "").lower() == "true"
    
    # 检查是否有 Bot 配置
    bot_result = await db.execute(select(func.count()).select_from(BotConfig))
    bot_count = bot_result.scalar() or 0
    
    return {
        "needs_setup": not onboarding_completed,
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


@router.get("/background-tasks/diagnostics", response_model=BackgroundTaskDiagnosticsResponse)
async def get_background_task_diagnostics(
    limit: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    diagnostics: SystemDiagnosticsService = Depends(
        get_system_diagnostics_service
    ),
    _: None = Depends(require_api_token),
):
    """Return failed background work and retry details for operator diagnostics."""
    return await diagnostics.build_failure_details(db, limit=limit)


@router.get("/background-tasks/runs/{run_id}", response_model=BackgroundTaskRunResponse)
async def get_background_task_run(
    run_id: str,
    diagnostics: SystemDiagnosticsService = Depends(
        get_system_diagnostics_service
    ),
    _: None = Depends(require_api_token),
):
    """Return one recent background task run by id for deep-linked result pages."""
    needle = run_id.strip()
    if not needle:
        raise HTTPException(
            status_code=400,
            detail=build_error_payload(
                message="run_id is required",
                code="run_id_required",
            ),
        )
    run = await diagnostics.get_run(needle)
    if run is not None:
        return run
    raise HTTPException(
        status_code=404,
        detail=build_error_payload(
            message=f"Background task run not found: {needle}",
            code="background_task_run_not_found",
        ),
    )


@router.get("/background-tasks/metrics")
async def get_background_task_metrics(
    db: AsyncSession = Depends(get_db),
    diagnostics: SystemDiagnosticsService = Depends(
        get_system_diagnostics_service
    ),
    _: None = Depends(require_api_token),
):
    """Export lightweight Prometheus-style background task metrics."""
    body = await diagnostics.build_metrics_text(db)
    return Response(body, media_type="text/plain; version=0.0.4")

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

@router.delete(
    "/settings/{key}",
    response_model=SystemSettingDeleteResponse,
)
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


@router.get("/favorites-sync/status", response_model=FavoritesSyncStatusResponse)
async def get_favorites_sync_status(
    request: Request,
    service: FavoritesSyncService = Depends(get_favorites_sync_service),
    _: None = Depends(require_api_token),
):
    """Get favorites sync runtime/settings status for frontend panel."""
    sync_task = getattr(request.app.state, "favorites_sync_task", None)
    return await service.get_status(
        sync_task=sync_task,
        request_id=getattr(request.state, "request_id", None),
    )


@router.get("/platform-health")
async def get_platform_health(
    request: Request,
    service: PlatformHealthService = Depends(get_platform_health_service),
    _: None = Depends(require_api_token),
):
    """Aggregate platform login, cookie and favorites-sync health in one API."""
    sync_task = getattr(request.app.state, "favorites_sync_task", None)
    return await service.get_status(
        sync_task=sync_task,
        request_id=getattr(request.state, "request_id", None),
    )


@router.get("/ai/capabilities")
async def get_ai_capabilities(
    db: AsyncSession = Depends(get_db),
    diagnostics: AIDiagnosticsService = Depends(get_ai_diagnostics_service),
    _: None = Depends(require_api_token),
):
    """Return user-facing AI capability status before advanced model fields."""
    capabilities = await diagnostics.build_capabilities(db)
    return {"capabilities": capabilities}


@router.post(
    "/ai/connectivity-test",
    response_model=AIConnectivityTestResponse,
    response_model_exclude_none=True,
)
async def test_ai_connectivity(
    payload: AIConnectivityTestRequest,
    diagnostics: AIDiagnosticsService = Depends(get_ai_diagnostics_service),
    _: None = Depends(require_api_token),
):
    """Run a real one-shot AI provider connectivity test."""
    try:
        return await diagnostics.test_connectivity(payload.target)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.post("/ai/models", response_model=AIModelDiscoveryResponse)
async def discover_ai_models(
    payload: AIModelDiscoveryRequest,
    diagnostics: AIDiagnosticsService = Depends(get_ai_diagnostics_service),
    _: None = Depends(require_api_token),
):
    """Discover models exposed by a configured OpenAI-compatible provider."""
    try:
        return await diagnostics.discover_models(payload.target)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"model discovery failed: {exc}")
@router.post(
    "/platform-health/parse-test",
    response_model=PlatformParseTestResponse,
    response_model_exclude_none=True,
)
async def test_platform_parse(
    payload: PlatformParseTestRequest,
    diagnostics: AIDiagnosticsService = Depends(get_ai_diagnostics_service),
    _: None = Depends(require_api_token),
):
    """Run a one-shot platform parser test without importing the content."""
    try:
        return await diagnostics.test_platform_parse(payload.platform, payload.url)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.post(
    "/favorites-sync/sync",
    response_model=FavoritesSyncAcceptedResponse,
    response_model_exclude_none=True,
    status_code=202,
)
async def trigger_favorites_sync(
    request: Request,
    background_tasks: BackgroundTasks,
    body: FavoritesSyncTriggerRequest | None = Body(default=None),
    service: FavoritesSyncService = Depends(get_favorites_sync_service),
    _: None = Depends(require_api_token),
):
    """Trigger one round of favorites sync (all platforms or single platform)."""
    sync_task = getattr(request.app.state, "favorites_sync_task", None)
    platform = ((body.platform if body else "") or "").strip().lower()
    force = bool(body.force) if body else False
    try:
        return await service.trigger(
            sync_task=sync_task,
            platform=platform,
            force=force,
            request_id=getattr(request.state, "request_id", None),
            add_task=background_tasks.add_task,
        )
    except FavoritesSyncServiceError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)


@router.post("/favorites-sync/preview", response_model=FavoritesSyncPreviewResponse)
async def preview_favorites_sync(
    request: Request,
    body: FavoritesSyncPreviewRequest | None = Body(default=None),
    service: FavoritesSyncService = Depends(get_favorites_sync_service),
    _: None = Depends(require_api_token),
):
    """Preview one favorites sync round without importing content or advancing cursors."""
    sync_task = getattr(request.app.state, "favorites_sync_task", None)
    platform = ((body.platform if body else "") or "").strip().lower()
    try:
        return await service.preview(
            sync_task=sync_task,
            platform=platform,
            request_id=getattr(request.state, "request_id", None),
        )
    except FavoritesSyncServiceError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)


@router.post(
    "/favorites-sync/runs/{run_id}/retry",
    response_model=FavoritesSyncAcceptedResponse,
    response_model_exclude_none=True,
    status_code=202,
)
async def retry_favorites_sync_run(
    run_id: str,
    request: Request,
    background_tasks: BackgroundTasks,
    service: FavoritesSyncService = Depends(get_favorites_sync_service),
    _: None = Depends(require_api_token),
):
    """Retry a previous favorites sync run using its recorded scope."""
    sync_task = getattr(request.app.state, "favorites_sync_task", None)
    try:
        return await service.retry_run(
            sync_task=sync_task,
            source_run_id=run_id,
            request_id=getattr(request.state, "request_id", None),
            add_task=background_tasks.add_task,
        )
    except FavoritesSyncServiceError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)


@router.post(
    "/favorites-sync/items/retry",
    response_model=FavoritesSyncItemRetryResponse,
    response_model_exclude_none=True,
)
async def retry_favorites_sync_item(
    body: FavoritesSyncItemRetryRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
    service: FavoritesSyncService = Depends(get_favorites_sync_service),
    _: None = Depends(require_api_token),
):
    """Retry importing one failed favorites item without advancing sync cursor."""
    policy_task = getattr(request.app.state, "favorites_sync_task", None)
    try:
        return await service.retry_item(
            body=body,
            db=db,
            policy_task=policy_task,
            request_id=getattr(request.state, "request_id", None),
        )
    except FavoritesSyncServiceError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)


@router.post(
    "/favorites-sync/items/batch-retry",
    response_model=FavoritesSyncItemsRetryResponse,
    response_model_exclude_none=True,
)
async def retry_favorites_sync_items(
    body: FavoritesSyncItemsRetryRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
    service: FavoritesSyncService = Depends(get_favorites_sync_service),
    _: None = Depends(require_api_token),
):
    """Retry importing multiple failed favorites items in one observable run."""
    policy_task = getattr(request.app.state, "favorites_sync_task", None)
    try:
        return await service.retry_items(
            body=body,
            db=db,
            policy_task=policy_task,
            request_id=getattr(request.state, "request_id", None),
        )
    except FavoritesSyncServiceError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
