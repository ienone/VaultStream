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
from fastapi import APIRouter, Depends, HTTPException, Query, Request, Body, Response
from pydantic import BaseModel
from sqlalchemy import Integer, select, and_, func, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db, get_database_health
from app.core.db_adapter import AsyncSessionLocal
from app.models import (
    BotConfig,
    Content,
    ContentQueueItem,
    DiscoverySource,
    DiscoveryState,
    Platform,
    QueueItemStatus,
    SystemSetting,
    Task,
    TaskStatus,
)
from app.schemas import (
    SystemSettingResponse, SystemSettingUpdate, DashboardStats, 
    QueueStats, TagStats, QueueOverviewStats, DistributionStatusStats,
    FavoritesSyncItemRetryRequest,
    FavoritesSyncPreviewRequest, FavoritesSyncPreviewResponse,
    FavoritesSyncTriggerRequest, BackgroundTaskDiagnosticsResponse,
)
from app.core.logging import logger
from app.core.dependencies import require_api_token
from app.core.api_errors import build_error_payload
from app.adapters.favorites.errors import FavoritesFetchError
from app.adapters.storage import get_storage_backend, LocalStorageBackend
from app.core.queue import task_queue
from app.services.background_task_state import (
    get_background_task_states,
    get_recent_task_runs,
    record_task_run_error,
    record_task_run_started,
    record_task_run_success,
)
from app.services.embedding_service import EmbeddingService
from app.services.settings_service import get_setting_value
from app.utils.sensitive_display import extract_secret_value
from app.utils.sensitive_display import as_configured_placeholder, is_sensitive_setting_key

router = APIRouter()

_storage_usage_cache: dict = {"value": 0, "expires_at": 0.0}
_STORAGE_CACHE_TTL = 300  # 5 minutes


class AIConnectivityTestRequest(BaseModel):
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


def _platform_label(platform: str) -> str:
    labels = {
        "zhihu": "知乎",
        "xiaohongshu": "小红书",
        "twitter": "Twitter / X",
        "weibo": "微博",
        "bilibili": "Bilibili",
    }
    return labels.get(platform, platform)


def _platform_cookie_keys(platform: str) -> list[str]:
    if platform == "bilibili":
        return ["bilibili_cookie", "bilibili_bili_jct"]
    return [f"{platform}_cookie"]


async def _is_any_platform_cookie_configured(platform: str) -> bool:
    from app.services.settings_service import get_setting_value

    for key in _platform_cookie_keys(platform):
        value = await get_setting_value(key)
        if isinstance(value, str) and value.strip():
            return True
    return False


def _latest_favorites_run_for_platform(
    runs: list[dict[str, Any]],
    platform: str,
) -> dict[str, Any] | None:
    for run in runs:
        scope = str(run.get("scope") or "all").strip().lower()
        if scope == platform or scope == "all":
            return run
    return None


def _is_configured_value(value: Any) -> bool:
    text = extract_secret_value(value)
    return isinstance(text, str) and bool(text.strip())


async def _get_configured_setting(key: str, default: Any = None) -> Any:
    return await get_setting_value(key, default)


async def _llm_key_configured(prefix: str) -> bool:
    return _is_configured_value(await _get_configured_setting(f"{prefix}_api_key"))


def _capability_item(
    key: str,
    label: str,
    status: str,
    summary: str,
    *,
    issues: list[str] | None = None,
    actions: list[str] | None = None,
    details: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "key": key,
        "label": label,
        "status": status,
        "available": status == "available",
        "summary": summary,
        "issues": issues or [],
        "actions": actions or [],
        "details": details or {},
    }


async def _build_ai_capabilities(db: AsyncSession) -> list[dict[str, Any]]:
    text_ready = await _llm_key_configured("text_llm")
    vision_ready = await _llm_key_configured("vision_llm")
    summary_key_ready = _is_configured_value(await _get_configured_setting("summary_api_key"))
    summary_enabled = bool(await _get_configured_setting("enable_auto_summary", settings.enable_auto_summary))
    embedding_ready = _is_configured_value(await _get_configured_setting("embedding_api_key"))
    semantic_status = await EmbeddingService().get_index_status(session=db)
    indexed_total = int(semantic_status.get("indexed_total") or 0)
    connectivity = await _latest_ai_connectivity_by_target()

    capabilities: list[dict[str, Any]] = []

    if text_ready and vision_ready:
        capabilities.append(
            _capability_item(
                "content_understanding",
                "内容理解",
                "available",
                "文本与视觉模型均已配置，可用于解析增强和复杂内容理解。",
                details={
                    "text_llm": True,
                    "vision_llm": True,
                    "connectivity": connectivity.get("text_llm") or connectivity.get("vision_llm"),
                },
            )
        )
    elif text_ready or vision_ready:
        missing = "视觉模型未配置" if text_ready else "文本模型未配置"
        target = "text_llm" if text_ready else "vision_llm"
        capabilities.append(
            _capability_item(
                "content_understanding",
                "内容理解",
                "partial",
                "已有部分模型配置，部分解析增强能力可用。",
                issues=[missing],
                actions=["补齐文本与视觉模型密钥"],
                details={
                    "text_llm": text_ready,
                    "vision_llm": vision_ready,
                    "connectivity": connectivity.get(target),
                },
            )
        )
    else:
        capabilities.append(
            _capability_item(
                "content_understanding",
                "内容理解",
                "unavailable",
                "未配置文本或视觉模型，AI 内容理解能力不可用。",
                issues=["text_llm_api_key 与 vision_llm_api_key 均未配置"],
                actions=["配置文本或视觉 LLM 密钥"],
                details={"text_llm": False, "vision_llm": False, "connectivity": None},
            )
        )

    if not summary_enabled:
        capabilities.append(
            _capability_item(
                "summary_generation",
                "摘要生成",
                "disabled",
                "自动摘要开关已关闭。",
                actions=["开启自动摘要"],
                details={
                    "enabled": False,
                    "summary_key": summary_key_ready,
                    "connectivity": connectivity.get("summary_generation"),
                },
            )
        )
    elif summary_key_ready:
        capabilities.append(
            _capability_item(
                "summary_generation",
                "摘要生成",
                "available",
                "自动摘要已开启，摘要模型密钥已配置。",
                details={
                    "enabled": True,
                    "summary_key": True,
                    "connectivity": connectivity.get("summary_generation"),
                },
            )
        )
    else:
        capabilities.append(
            _capability_item(
                "summary_generation",
                "摘要生成",
                "unavailable",
                "自动摘要已开启，但摘要模型密钥缺失。",
                issues=["summary_api_key 未配置"],
                actions=["配置摘要模型密钥或关闭自动摘要"],
                details={
                    "enabled": True,
                    "summary_key": False,
                    "connectivity": connectivity.get("summary_generation"),
                },
            )
        )

    if not embedding_ready:
        capabilities.append(
            _capability_item(
                "semantic_search",
                "语义搜索",
                "unavailable",
                "Embedding 密钥未配置，无法生成或更新语义索引。",
                issues=["embedding_api_key 未配置"],
                actions=["配置 Embedding 密钥"],
                details={
                    "indexed_total": indexed_total,
                    "connectivity": connectivity.get("semantic_search"),
                    **semantic_status,
                },
            )
        )
    elif indexed_total <= 0:
        capabilities.append(
            _capability_item(
                "semantic_search",
                "语义搜索",
                "pending",
                "Embedding 已配置，但当前还没有已索引内容。",
                actions=["运行语义重建或等待新内容入库"],
                details={
                    "indexed_total": indexed_total,
                    "connectivity": connectivity.get("semantic_search"),
                    **semantic_status,
                },
            )
        )
    else:
        capabilities.append(
            _capability_item(
                "semantic_search",
                "语义搜索",
                "available",
                f"已有 {indexed_total} 条内容进入语义索引。",
                details={
                    "indexed_total": indexed_total,
                    "connectivity": connectivity.get("semantic_search"),
                    **semantic_status,
                },
            )
        )

    if text_ready or vision_ready:
        target = "text_llm" if text_ready else "vision_llm"
        capabilities.append(
            _capability_item(
                "agent",
                "Agent",
                "available",
                "Agent 可使用已配置的文本模型；缺少文本模型时会尝试回退到视觉模型。",
                details={
                    "text_llm": text_ready,
                    "vision_llm": vision_ready,
                    "connectivity": connectivity.get(target),
                },
            )
        )
    else:
        capabilities.append(
            _capability_item(
                "agent",
                "Agent",
                "unavailable",
                "Agent 需要至少一个可用的文本或视觉 LLM。",
                issues=["未配置可供 Agent 使用的 LLM 密钥"],
                actions=["配置 text_llm_api_key 或 vision_llm_api_key"],
                details={"text_llm": False, "vision_llm": False, "connectivity": None},
            )
        )

    return capabilities


async def _latest_ai_connectivity_by_target() -> dict[str, dict[str, Any]]:
    runs = await get_recent_task_runs("ai_connectivity_test", limit=20)
    latest: dict[str, dict[str, Any]] = {}
    for run in runs:
        target = str(run.get("target") or "")
        if not target or target in latest:
            continue
        latest[target] = {
            "run_id": run.get("run_id"),
            "status": run.get("status"),
            "started_at": run.get("started_at"),
            "finished_at": run.get("finished_at"),
            "error": run.get("error"),
            "result": run.get("result") if isinstance(run.get("result"), dict) else {},
        }
    return latest


def _normalize_ai_connectivity_target(target: str) -> str:
    normalized = (target or "").strip().lower()
    aliases = {
        "embedding": "semantic_search",
        "semantic": "semantic_search",
        "summary": "summary_generation",
        "text": "text_llm",
        "vision": "vision_llm",
        "agent": "text_llm",
    }
    normalized = aliases.get(normalized, normalized)
    if normalized not in {
        "text_llm",
        "vision_llm",
        "summary_generation",
        "semantic_search",
    }:
        raise ValueError("target must be text_llm, vision_llm, summary_generation or semantic_search")
    return normalized


async def _run_ai_connectivity_target(target: str) -> dict[str, Any]:
    if target in {"text_llm", "vision_llm"}:
        from langchain_core.messages import HumanMessage
        from app.core.llm_factory import LLMFactory

        llm = (
            await LLMFactory.get_text_llm()
            if target == "text_llm"
            else await LLMFactory.get_vision_llm()
        )
        if llm is None:
            raise RuntimeError(f"{target}_api_key is not configured or model initialization failed")
        response = await llm.ainvoke([HumanMessage(content="VaultStream connectivity test. Reply with OK.")])
        text = str(getattr(response, "content", "") or "").strip()
        return {"target": target, "response_present": bool(text), "preview": text[:120]}

    if target == "semantic_search":
        vector = await EmbeddingService().embed_query("VaultStream connectivity test")
        return {"target": target, "dimension": len(vector), "response_present": bool(vector)}

    from app.services.content_summary_service import _get_summary_llm_config

    key, model, api_version = await _get_summary_llm_config()
    if not key:
        raise RuntimeError("summary_api_key is not configured")

    from google import genai
    from google.genai import types

    client = genai.Client(api_key=key, http_options={"api_version": api_version})

    def _call():
        return client.models.generate_content(
            model=model,
            contents="VaultStream connectivity test. Reply with OK.",
            config=types.GenerateContentConfig(max_output_tokens=16),
        )

    response = await asyncio.to_thread(_call)
    text = str(getattr(response, "text", "") or "").strip()
    return {
        "target": target,
        "model": model,
        "api_version": api_version,
        "response_present": bool(text or response),
        "preview": text[:120],
    }


def _normalize_parse_test_platform(platform: str) -> str:
    normalized = (platform or "").strip().lower()
    aliases = {
        "x": "twitter",
        "twitter_x": "twitter",
        "telegram_channel": "telegram",
    }
    normalized = aliases.get(normalized, normalized)
    valid = {item.value for item in Platform}
    if normalized not in valid:
        raise ValueError("platform is not supported")
    return normalized


async def _run_platform_parse_test(platform: str, url: str) -> dict[str, Any]:
    from app.adapters import AdapterFactory, open_adapter

    text = (url or "").strip()
    if not text:
        raise ValueError("url is required")
    if not text.startswith(("http://", "https://")):
        raise ValueError("url must start with http:// or https://")

    platform_enum = Platform(platform)
    detected = AdapterFactory.detect_platform(text)
    if platform_enum != Platform.UNIVERSAL and detected != Platform.UNIVERSAL and detected != platform_enum:
        raise ValueError(f"url is detected as {detected.value}, not {platform}")

    async with open_adapter(platform_enum) as adapter:
        parsed = await adapter.parse(text)

    return {
        "platform": platform,
        "url": text,
        "detected_platform": detected.value,
        "title": parsed.title,
        "content_type": parsed.content_type,
        "layout_type": parsed.layout_type.value if hasattr(parsed.layout_type, "value") else str(parsed.layout_type),
        "author": parsed.author,
        "media_count": len(parsed.media_urls or []),
    }


async def _count_by_status(db: AsyncSession, model, status_column, enum_cls) -> dict[str, int]:
    rows = (
        await db.execute(
            select(status_column, func.count())
            .select_from(model)
            .group_by(status_column)
        )
    ).all()
    counts = {item.value: 0 for item in enum_cls}
    for status, count in rows:
        key = status.value if hasattr(status, "value") else str(status)
        counts[key] = int(count or 0)
    return counts


async def _build_background_diagnostics(db: AsyncSession) -> dict[str, Any]:
    task_counts = await _count_by_status(db, Task, Task.status, TaskStatus)
    queue_counts = await _count_by_status(
        db,
        ContentQueueItem,
        ContentQueueItem.status,
        QueueItemStatus,
    )
    retryable_distribution = (
        await db.execute(
            select(func.count())
            .select_from(ContentQueueItem)
            .where(ContentQueueItem.status == QueueItemStatus.FAILED)
            .where(ContentQueueItem.attempt_count < ContentQueueItem.max_attempts)
        )
    ).scalar() or 0

    source_stats = (
        await db.execute(
            select(
                func.count(DiscoverySource.id),
                func.max(DiscoverySource.last_sync_at),
                func.sum(
                    func.cast(DiscoverySource.last_error.is_not(None), Integer)
                ),
            )
        )
    ).one()
    task_states = await get_background_task_states()

    return {
        "parse_tasks": {
            "pending": task_counts.get(TaskStatus.PENDING.value, 0),
            "running": task_counts.get(TaskStatus.RUNNING.value, 0),
            "failed": task_counts.get(TaskStatus.FAILED.value, 0),
            "completed": task_counts.get(TaskStatus.COMPLETED.value, 0),
        },
        "distribution_queue": {
            "scheduled": queue_counts.get(QueueItemStatus.SCHEDULED.value, 0),
            "processing": queue_counts.get(QueueItemStatus.PROCESSING.value, 0),
            "failed": queue_counts.get(QueueItemStatus.FAILED.value, 0),
            "success": queue_counts.get(QueueItemStatus.SUCCESS.value, 0),
            "retryable_failed": int(retryable_distribution),
        },
        "discovery_sync": {
            "source_count": int(source_stats[0] or 0),
            "last_success_at": source_stats[1],
            "last_error_count": int(source_stats[2] or 0),
        },
        "task_states": task_states,
    }


def _serialize_task_state(task_name: str, state: dict[str, Any]) -> dict[str, Any]:
    known = {
        "task",
        "status",
        "last_started_at",
        "last_success_at",
        "last_error_at",
        "last_error",
        "run_count",
        "error_count",
    }
    return {
        "task": str(state.get("task") or task_name),
        "status": str(state.get("status") or "unknown"),
        "last_started_at": state.get("last_started_at"),
        "last_success_at": state.get("last_success_at"),
        "last_error_at": state.get("last_error_at"),
        "last_error": state.get("last_error"),
        "run_count": int(state.get("run_count") or 0),
        "error_count": int(state.get("error_count") or 0),
        "metrics": {k: v for k, v in state.items() if k not in known},
    }


async def _build_background_failure_details(
    db: AsyncSession,
    *,
    limit: int = 20,
) -> dict[str, Any]:
    summary = await _build_background_diagnostics(db)
    task_states_raw = await get_background_task_states()
    task_states = [
        _serialize_task_state(name, state)
        for name, state in sorted(task_states_raw.items())
    ]
    recent_task_runs: list[dict[str, Any]] = []
    for task_name in (
        "content_parse",
        "content_reparse",
        "content_embedding",
        "content_summary",
        "discovery_patrol",
        "discovery_source_test",
        "discovery_sync",
        "distribution_push",
        "distribution_schedule",
        "distribution_worker_poll",
        "distribution_target_test",
        "distribution_target_send_test",
        "favorites_sync",
        "semantic_reindex",
        "ai_connectivity_test",
        "platform_parse_test",
    ):
        recent_task_runs.extend(await get_recent_task_runs(task_name, limit=limit))
    recent_task_runs.sort(
        key=lambda run: str(run.get("started_at") or ""),
        reverse=True,
    )
    recent_task_runs = recent_task_runs[:limit]

    failed_tasks_rows = (
        await db.execute(
            select(Task)
            .where(Task.status == TaskStatus.FAILED)
            .order_by(Task.completed_at.desc().nullslast(), Task.created_at.desc())
            .limit(limit)
        )
    ).scalars().all()
    failed_parse_tasks = []
    for task in failed_tasks_rows:
        payload = task.payload if isinstance(task.payload, dict) else {}
        content_id_raw = payload.get("content_id")
        failed_parse_tasks.append(
            {
                "id": task.id,
                "task_type": task.task_type,
                "content_id": int(content_id_raw) if content_id_raw is not None else None,
                "retry_count": task.retry_count or 0,
                "max_retries": task.max_retries or 0,
                "retryable": (task.retry_count or 0) < (task.max_retries or 0),
                "last_error": task.last_error,
                "created_at": task.created_at,
                "started_at": task.started_at,
                "completed_at": task.completed_at,
            }
        )

    failed_queue_rows = (
        await db.execute(
            select(ContentQueueItem, Content.title)
            .join(Content, Content.id == ContentQueueItem.content_id, isouter=True)
            .where(ContentQueueItem.status == QueueItemStatus.FAILED)
            .order_by(ContentQueueItem.last_error_at.desc().nullslast(), ContentQueueItem.updated_at.desc())
            .limit(limit)
        )
    ).all()
    failed_distribution_items = [
        {
            "id": item.id,
            "content_id": item.content_id,
            "title": title,
            "target_platform": item.target_platform,
            "target_id": item.target_id,
            "attempt_count": item.attempt_count or 0,
            "max_attempts": item.max_attempts or 0,
            "retryable": (item.attempt_count or 0) < (item.max_attempts or 0),
            "next_attempt_at": item.next_attempt_at,
            "last_error": item.last_error,
            "last_error_type": item.last_error_type,
            "last_error_at": item.last_error_at,
            "updated_at": item.updated_at,
        }
        for item, title in failed_queue_rows
    ]

    failed_sources = (
        await db.execute(
            select(DiscoverySource)
            .where(DiscoverySource.last_error.is_not(None))
            .order_by(DiscoverySource.last_sync_at.desc().nullslast(), DiscoverySource.updated_at.desc())
            .limit(limit)
        )
    ).scalars().all()
    failed_discovery_sources = [
        {
            "id": source.id,
            "name": source.name,
            "kind": source.kind.value if hasattr(source.kind, "value") else str(source.kind),
            "enabled": bool(source.enabled),
            "last_sync_at": source.last_sync_at,
            "last_error": source.last_error,
        }
        for source in failed_sources
    ]

    return {
        "summary": summary,
        "task_states": task_states,
        "recent_task_runs": recent_task_runs,
        "failed_parse_tasks": failed_parse_tasks,
        "failed_distribution_items": failed_distribution_items,
        "failed_discovery_sources": failed_discovery_sources,
    }


async def _build_provider_diagnostics(db: AsyncSession) -> dict[str, Any]:
    setting_rows = (
        await db.execute(
            select(SystemSetting.key, SystemSetting.value).where(
                SystemSetting.key.in_(
                    [
                        "text_llm_api_key",
                        "text_llm_model",
                        "summary_api_key",
                        "summary_model",
                        "embedding_api_key",
                        "embedding_model",
                    ]
                )
            )
        )
    ).all()
    stored = {key: value for key, value in setting_rows}

    enabled_bot_count = (
        await db.execute(
            select(func.count()).select_from(BotConfig).where(BotConfig.enabled == True)  # noqa: E712
        )
    ).scalar() or 0

    return {
        "text_llm": {
            "configured": bool(stored.get("text_llm_api_key") or settings.text_llm_api_key),
            "model": stored.get("text_llm_model") or settings.text_llm_model,
        },
        "summary": {
            "configured": bool(stored.get("summary_api_key") or settings.summary_api_key),
            "model": stored.get("summary_model") or settings.summary_model,
        },
        "embedding": {
            "configured": bool(stored.get("embedding_api_key") or settings.embedding_api_key),
            "model": stored.get("embedding_model") or settings.embedding_model,
        },
        "bots": {
            "enabled_configs": int(enabled_bot_count),
        },
    }


@router.get("/health")
async def health_check():
    """健康检查"""
    queue_ok = await task_queue.ping()
    db_health = await get_database_health()
    db_ok = db_health["status"] == "ok"
    fts_ok = db_health.get("fts", {}).get("available", False)
    queue_size = await task_queue.get_queue_size()
    async with AsyncSessionLocal() as db:
        background = await _build_background_diagnostics(db)
        providers = await _build_provider_diagnostics(db)
    
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


@router.get("/background-tasks/diagnostics", response_model=BackgroundTaskDiagnosticsResponse)
async def get_background_task_diagnostics(
    limit: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """Return failed background work and retry details for operator diagnostics."""
    return await _build_background_failure_details(db, limit=limit)


@router.get("/background-tasks/metrics")
async def get_background_task_metrics(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """Export lightweight Prometheus-style background task metrics."""
    diagnostics = await _build_background_diagnostics(db)
    parse = diagnostics["parse_tasks"]
    distribution = diagnostics["distribution_queue"]
    discovery = diagnostics["discovery_sync"]
    lines = [
        "# HELP vaultstream_parse_tasks Number of parse tasks by status.",
        "# TYPE vaultstream_parse_tasks gauge",
        *[
            f'vaultstream_parse_tasks{{status="{status}"}} {count}'
            for status, count in sorted(parse.items())
        ],
        "# HELP vaultstream_distribution_queue Number of distribution queue items by status.",
        "# TYPE vaultstream_distribution_queue gauge",
        *[
            f'vaultstream_distribution_queue{{status="{status}"}} {count}'
            for status, count in sorted(distribution.items())
        ],
        "# HELP vaultstream_discovery_sources Discovery source diagnostics.",
        "# TYPE vaultstream_discovery_sources gauge",
        f'vaultstream_discovery_sources{{state="configured"}} {discovery["source_count"]}',
        f'vaultstream_discovery_sources{{state="last_error"}} {discovery["last_error_count"]}',
    ]
    return Response("\n".join(lines) + "\n", media_type="text/plain; version=0.0.4")

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
        "recent_runs": await get_recent_task_runs("favorites_sync", limit=10),
        "platforms": platforms,
    }


@router.get("/platform-health")
async def get_platform_health(
    request: Request,
    _: None = Depends(require_api_token),
):
    """Aggregate platform login, cookie and favorites-sync health in one API."""
    from app.services.browser_auth_service import browser_auth_service
    from app.services.settings_service import get_setting_value
    from app.tasks.favorites_sync import FavoritesSyncTask

    sync_task = getattr(request.app.state, "favorites_sync_task", None)
    if sync_task is None:
        sync_task = FavoritesSyncTask()

    enabled_favorites = await sync_task.load_enabled_platforms()
    recent_runs = await get_recent_task_runs("favorites_sync", limit=20)
    supported_favorites = set(sync_task.get_supported_platforms())
    browser_platforms = set(browser_auth_service.platforms.keys())
    ordered = ["zhihu", "xiaohongshu", "twitter", "weibo", "bilibili"]
    platforms = [
        platform
        for platform in ordered + sorted((supported_favorites | browser_platforms) - set(ordered))
        if platform in supported_favorites or platform in browser_platforms or platform == "bilibili"
    ]

    items: list[dict[str, Any]] = []
    for platform in platforms:
        cookie_configured = await _is_any_platform_cookie_configured(platform)
        browser_auth_supported = platform in browser_platforms
        browser_auth_valid: bool | None = None
        browser_auth_error: str | None = None
        if browser_auth_supported and cookie_configured:
            try:
                browser_auth_valid = await browser_auth_service.check_platform_status(platform)
            except Exception as e:
                browser_auth_valid = False
                browser_auth_error = str(e)
                logger.warning("[platform health] browser auth check failed for {}: {}", platform, e)

        favorites_supported = platform in supported_favorites
        favorites_enabled = platform in enabled_favorites
        favorites_authenticated: bool | None = None
        favorites_available = favorites_supported
        favorites_error: str | None = None
        favorites_status_error: dict[str, Any] | None = None
        favorites_last_result = await get_setting_value(f"favorites_sync_last_result_{platform}")

        if favorites_supported and favorites_enabled:
            fetcher_cls = sync_task.get_fetcher_cls(platform)
            if fetcher_cls is not None:
                try:
                    favorites_authenticated = await fetcher_cls().check_auth()
                except ImportError as e:
                    favorites_available = False
                    favorites_authenticated = False
                    favorites_error = str(e)
                    favorites_status_error = build_error_payload(
                        message=str(e),
                        code="dependency_missing",
                        hint="依赖缺失，请检查后端运行环境",
                        request_id=getattr(request.state, "request_id", None),
                    )
                except FavoritesFetchError as e:
                    favorites_available = e.code != "cli_unavailable"
                    favorites_authenticated = False
                    favorites_error = e.message
                    favorites_status_error = {
                        "detail": e.message,
                        **e.as_dict(),
                        "request_id": getattr(request.state, "request_id", None),
                    }
                except Exception as e:
                    favorites_available = False
                    favorites_authenticated = False
                    favorites_error = str(e)
                    favorites_status_error = build_error_payload(
                        message=str(e),
                        code="auth_check_failed",
                        hint="认证检查失败，请稍后重试",
                        request_id=getattr(request.state, "request_id", None),
                    )
                    logger.warning("[platform health] favorites auth check failed for {}: {}", platform, e)

        latest_favorites_run = _latest_favorites_run_for_platform(recent_runs, platform)
        issues: list[str] = []
        if browser_auth_supported and not cookie_configured:
            issues.append("未配置登录 Cookie")
        if browser_auth_valid is False:
            issues.append("登录状态不可用")
        if favorites_enabled and favorites_authenticated is False:
            issues.append("收藏同步认证失败")
        if latest_favorites_run and latest_favorites_run.get("status") == "error":
            issues.append("最近收藏同步失败")

        if issues:
            health = "error"
        elif favorites_enabled or cookie_configured:
            health = "ok"
        else:
            health = "inactive"

        items.append(
            {
                "platform": platform,
                "label": _platform_label(platform),
                "health": health,
                "issues": issues,
                "auth": {
                    "cookie_configured": cookie_configured,
                    "browser_auth_supported": browser_auth_supported,
                    "browser_auth_valid": browser_auth_valid,
                    "error": browser_auth_error,
                },
                "favorites_sync": {
                    "supported": favorites_supported,
                    "enabled": favorites_enabled,
                    "available": favorites_available,
                    "authenticated": favorites_authenticated,
                    "last_result": favorites_last_result
                    if isinstance(favorites_last_result, dict)
                    else None,
                    "last_run": latest_favorites_run,
                    "error": favorites_error,
                    "status_error": favorites_status_error,
                },
            }
        )

    return {
        "platforms": items,
        "recent_favorites_runs": recent_runs[:10],
    }


@router.get("/ai/capabilities")
async def get_ai_capabilities(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """Return user-facing AI capability status before advanced model fields."""
    capabilities = await _build_ai_capabilities(db)
    return {"capabilities": capabilities}


@router.post("/ai/connectivity-test")
async def test_ai_connectivity(
    payload: AIConnectivityTestRequest,
    _: None = Depends(require_api_token),
):
    """Run a real one-shot AI provider connectivity test."""
    try:
        target = _normalize_ai_connectivity_target(payload.target)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    run = await record_task_run_started(
        "ai_connectivity_test",
        trigger="manual",
        target=target,
    )
    started = time.perf_counter()
    try:
        result = await _run_ai_connectivity_target(target)
        elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
        result = {**result, "elapsed_ms": elapsed_ms}
        await record_task_run_success(
            "ai_connectivity_test",
            run["run_id"],
            **result,
        )
        return {
            "run_id": run["run_id"],
            "target": target,
            "status": "success",
            "ok": True,
            **result,
        }
    except Exception as exc:
        elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
        await record_task_run_error(
            "ai_connectivity_test",
            run["run_id"],
            exc,
            trigger="manual",
            target=target,
            elapsed_ms=elapsed_ms,
        )
        return {
            "run_id": run["run_id"],
            "target": target,
            "status": "error",
            "ok": False,
            "error": str(exc)[:1000],
            "elapsed_ms": elapsed_ms,
        }


@router.post("/platform-health/parse-test")
async def test_platform_parse(
    payload: PlatformParseTestRequest,
    _: None = Depends(require_api_token),
):
    """Run a one-shot platform parser test without importing the content."""
    try:
        platform = _normalize_parse_test_platform(payload.platform)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    run = await record_task_run_started(
        "platform_parse_test",
        trigger="manual",
        platform=platform,
        url=payload.url,
    )
    started = time.perf_counter()
    try:
        result = await _run_platform_parse_test(platform, payload.url)
        elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
        result = {**result, "elapsed_ms": elapsed_ms}
        await record_task_run_success(
            "platform_parse_test",
            run["run_id"],
            **result,
        )
        return {
            "run_id": run["run_id"],
            "platform": platform,
            "status": "success",
            "ok": True,
            **result,
        }
    except ValueError as exc:
        elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
        await record_task_run_error(
            "platform_parse_test",
            run["run_id"],
            exc,
            trigger="manual",
            platform=platform,
            url=payload.url,
            elapsed_ms=elapsed_ms,
        )
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
        await record_task_run_error(
            "platform_parse_test",
            run["run_id"],
            exc,
            trigger="manual",
            platform=platform,
            url=payload.url,
            elapsed_ms=elapsed_ms,
        )
        return {
            "run_id": run["run_id"],
            "platform": platform,
            "status": "error",
            "ok": False,
            "error": str(exc)[:1000],
            "elapsed_ms": elapsed_ms,
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
        run = await sync_task.create_run(platform=platform, trigger="manual")
        asyncio.create_task(
            sync_task.sync_platform_by_name(
                platform,
                run_id=run["run_id"],
                trigger="manual",
            )
        )
        return {"status": "accepted", "platform": platform, "run_id": run["run_id"]}

    run = await sync_task.create_run(platform=None, trigger="manual")
    asyncio.create_task(
        sync_task.sync_all_platforms_once(
            run_id=run["run_id"],
            trigger="manual",
        )
    )
    return {"status": "accepted", "platform": "all", "run_id": run["run_id"]}


@router.post("/favorites-sync/preview", response_model=FavoritesSyncPreviewResponse)
async def preview_favorites_sync(
    request: Request,
    body: FavoritesSyncPreviewRequest | None = Body(default=None),
    _: None = Depends(require_api_token),
):
    """Preview one favorites sync round without importing content or advancing cursors."""
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
        preview = await sync_task.preview_platform_by_name(platform)
        return FavoritesSyncPreviewResponse(
            platform=platform,
            status=preview.get("status", "unknown"),
            fetched=int(preview.get("fetched") or 0),
            unique=int(preview.get("unique") or 0),
            existing=int(preview.get("existing") or 0),
            estimated_new=int(preview.get("estimated_new") or 0),
            skipped=int(preview.get("skipped") or 0),
            platforms=[preview],
        )

    return await sync_task.preview_all_platforms()


@router.post("/favorites-sync/runs/{run_id}/retry", status_code=202)
async def retry_favorites_sync_run(
    run_id: str,
    request: Request,
    _: None = Depends(require_api_token),
):
    """Retry a previous favorites sync run using its recorded scope."""
    sync_task = getattr(request.app.state, "favorites_sync_task", None)
    if sync_task is None:
        raise HTTPException(
            status_code=503,
            detail=build_error_payload(
                message="Favorites sync task is not running",
                code="favorites_task_unavailable",
                hint="请确认后端收藏同步任务已启动后重试",
                request_id=getattr(request.state, "request_id", None),
            ),
        )

    recent_runs = await get_recent_task_runs("favorites_sync", limit=20)
    source_run = next((run for run in recent_runs if run.get("run_id") == run_id), None)
    if source_run is None:
        raise HTTPException(
            status_code=404,
            detail=build_error_payload(
                message=f"Favorites sync run not found: {run_id}",
                code="favorites_sync_run_not_found",
                hint="请刷新同步状态后重试",
                request_id=getattr(request.state, "request_id", None),
            ),
        )

    scope = str(source_run.get("scope") or "all").strip().lower()
    platform = None if scope == "all" else scope
    if platform and platform not in sync_task.get_supported_platforms():
        raise HTTPException(
            status_code=400,
            detail=build_error_payload(
                message=f"Unsupported favorites sync scope: {scope}",
                code="unsupported_platform",
                hint="仅支持 zhihu / xiaohongshu / twitter",
                request_id=getattr(request.state, "request_id", None),
            ),
        )

    run = await sync_task.create_run(platform=platform, trigger="retry", retry_of=run_id)
    if platform:
        asyncio.create_task(
            sync_task.sync_platform_by_name(
                platform,
                run_id=run["run_id"],
                trigger="retry",
            )
        )
        return {
            "status": "accepted",
            "platform": platform,
            "run_id": run["run_id"],
            "retry_of": run_id,
        }

    asyncio.create_task(
        sync_task.sync_all_platforms_once(
            run_id=run["run_id"],
            trigger="retry",
        )
    )
    return {"status": "accepted", "platform": "all", "run_id": run["run_id"], "retry_of": run_id}


@router.post("/favorites-sync/items/retry")
async def retry_favorites_sync_item(
    body: FavoritesSyncItemRetryRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """Retry importing one failed favorites item without advancing sync cursor."""
    from app.services.content_service import ContentService
    from app.tasks.favorites_sync import FavoritesSyncTask

    platform = body.platform.strip().lower()
    url = body.url.strip()
    if not url:
        raise HTTPException(
            status_code=400,
            detail=build_error_payload(
                message="Favorites item URL is required",
                code="favorites_item_url_required",
                hint="请从失败项中选择带 URL 的记录后重试",
                request_id=getattr(request.state, "request_id", None),
            ),
        )
    supported_platforms = FavoritesSyncTask.get_fetcher_registry().keys()
    if platform not in supported_platforms:
        raise HTTPException(
            status_code=400,
            detail=build_error_payload(
                message=f"Unknown platform: {platform}",
                code="unsupported_platform",
                hint="仅支持 zhihu / xiaohongshu / twitter",
                request_id=getattr(request.state, "request_id", None),
            ),
        )

    run = await record_task_run_started(
        "favorites_sync",
        scope=platform,
        trigger="item_retry",
        platform=platform,
        url=url,
        title=body.title,
        item_id=body.item_id,
        source_run_id=body.source_run_id,
    )
    try:
        content = await ContentService(db).create_share(
            url=url,
            tags=[],
            source_name=f"favorites_sync:{platform}:retry",
            note=body.title,
            client_context={
                "platform": platform,
                "item_id": body.item_id,
                "source_run_id": body.source_run_id,
                "retry_run_id": run["run_id"],
            },
        )
        await record_task_run_success(
            "favorites_sync",
            run["run_id"],
            platform=platform,
            url=url,
            title=body.title,
            item_id=body.item_id,
            source_run_id=body.source_run_id,
            content_id=content.id,
            status="success",
        )
        return {
            "status": "success",
            "platform": platform,
            "run_id": run["run_id"],
            "content_id": content.id,
            "source_run_id": body.source_run_id,
        }
    except Exception as e:
        logger.bind(
            event="favorites_item_retry_failed",
            platform=platform,
            item_url=url,
            run_id=run["run_id"],
        ).exception("Favorites item retry failed: {}", e)
        await record_task_run_error(
            "favorites_sync",
            run["run_id"],
            e,
            platform=platform,
            url=url,
            title=body.title,
            item_id=body.item_id,
            source_run_id=body.source_run_id,
        )
        raise HTTPException(
            status_code=500,
            detail=build_error_payload(
                message=f"Favorites item retry failed: {str(e)}",
                code="favorites_item_retry_failed",
                hint="请确认失败项 URL 仍可访问，或改用整个平台同步重试",
                request_id=getattr(request.state, "request_id", None),
            ),
        ) from e
