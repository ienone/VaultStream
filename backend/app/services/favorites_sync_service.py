"""Favorites sync API orchestration outside the system router."""

from __future__ import annotations

from typing import Any, Callable

from sqlalchemy.ext.asyncio import AsyncSession

from app.adapters.favorites.base import FavoriteItem
from app.adapters.favorites.errors import FavoritesFetchError
from app.core.api_errors import build_error_payload
from app.core.logging import logger
from app.schemas import (
    FavoritesSyncItemRetryRequest,
    FavoritesSyncItemsRetryRequest,
    FavoritesSyncPreviewResponse,
)
from app.services.automation_policy import AutomationPolicyService
from app.services.background_task_state import (
    get_recent_task_runs,
    record_task_run_error,
    record_task_run_started,
    record_task_run_success,
)
from app.services.config_service import ConfigService
from app.tasks.favorites_sync import FavoritesSyncTask


class FavoritesSyncServiceError(Exception):
    def __init__(self, status_code: int, detail: dict[str, Any]):
        super().__init__(str(detail.get("detail") or "favorites sync failed"))
        self.status_code = status_code
        self.detail = detail


class FavoritesSyncService:
    def __init__(
        self,
        *,
        config_service: ConfigService | None = None,
        policy_service: AutomationPolicyService | None = None,
    ):
        self.config_service = config_service or ConfigService()
        self.policy_service = policy_service or AutomationPolicyService()

    @staticmethod
    def _error(
        status_code: int,
        *,
        message: str,
        code: str,
        hint: str,
        request_id: str | None,
        extra: dict[str, Any] | None = None,
    ) -> FavoritesSyncServiceError:
        return FavoritesSyncServiceError(
            status_code,
            build_error_payload(
                message=message,
                code=code,
                hint=hint,
                request_id=request_id,
                extra=extra,
            ),
        )

    @staticmethod
    def default_task() -> FavoritesSyncTask:
        return FavoritesSyncTask()

    async def require_manual_policy(
        self,
        *,
        platform: str,
        sync_task,
        request_id: str | None,
        force: bool = False,
    ) -> None:
        policy = await self.policy_service.favorites_platform_manual(
            platform,
            enabled_platforms=await sync_task.load_enabled_platforms(),
            force=force,
        )
        if policy.allowed:
            return
        raise self._error(
            409,
            message=policy.reason,
            code=policy.code,
            hint="启用该收藏同步平台，或通过现有策略配置允许手动执行。",
            request_id=request_id,
            extra={"policy": policy.as_dict()},
        )

    async def get_status(
        self,
        *,
        sync_task=None,
        request_id: str | None = None,
    ) -> dict[str, Any]:
        task = sync_task or FavoritesSyncTask(config_service=self.config_service)
        config = await self.config_service.get_favorites_sync_config(
            default_interval_minutes=FavoritesSyncTask._DEFAULT_INTERVAL_MINUTES,
            default_max_items=FavoritesSyncTask._DEFAULT_MAX_ITEMS,
            default_duplicate_strategy=FavoritesSyncTask._DEFAULT_DUPLICATE_STRATEGY,
            supported_platforms=task.get_supported_platforms(),
            allowed_duplicate_strategies=FavoritesSyncTask._DUPLICATE_STRATEGIES,
        )
        enabled_platforms = await task.load_enabled_platforms()

        platforms: list[dict[str, Any]] = []
        for platform in task.get_supported_platforms():
            fetcher_cls = task.get_fetcher_cls(platform)
            if fetcher_cls is None:
                continue

            authenticated = False
            available = True
            error: str | None = None
            status_error: dict[str, Any] | None = None
            if platform in enabled_platforms:
                try:
                    authenticated = await fetcher_cls().check_auth()
                except ImportError as exc:
                    available = False
                    error = str(exc)
                    status_error = build_error_payload(
                        message=str(exc),
                        code="dependency_missing",
                        hint="依赖缺失，请检查后端运行环境",
                        request_id=request_id,
                    )
                    logger.warning(
                        "[favorites status] check_auth import error for {}: {}",
                        platform,
                        exc,
                    )
                except FavoritesFetchError as exc:
                    available = exc.code != "cli_unavailable"
                    error = exc.message
                    status_error = {
                        "detail": exc.message,
                        **exc.as_dict(),
                        "request_id": request_id,
                    }
                    logger.warning(
                        "[favorites status] structured check_auth failure for {}: "
                        "code={} message={}",
                        platform,
                        exc.code,
                        exc.message,
                    )
                except Exception as exc:
                    available = False
                    error = str(exc)
                    status_error = build_error_payload(
                        message=str(exc),
                        code="auth_check_failed",
                        hint="认证检查失败，请稍后重试",
                        request_id=request_id,
                    )
                    logger.exception(
                        "[favorites status] check_auth failed for {}",
                        platform,
                    )

            platform_state = (
                await self.config_service.get_favorites_sync_platform_state(
                    platform,
                    default_rate_per_minute=task.default_rate_for(platform),
                )
            )
            platforms.append(
                {
                    "platform": platform,
                    "enabled": platform in enabled_platforms,
                    "available": available,
                    "authenticated": authenticated,
                    "rate_per_minute": platform_state.rate_per_minute,
                    "last_result": platform_state.last_result,
                    "error": error,
                    "status_error": status_error,
                }
            )

        return {
            "running": task.is_running(),
            "interval_minutes": config.interval_minutes,
            "max_items": config.max_items,
            "enabled_platforms": enabled_platforms,
            "last_sync_at": config.last_sync_at,
            "recent_runs": await get_recent_task_runs("favorites_sync", limit=10),
            "policies": {
                "duplicate_strategy": config.duplicate_strategy,
                "scope_strategy": config.scope_strategy,
                "first_sync_strategy": config.first_sync_strategy,
                "unfavorite_strategy": config.unfavorite_strategy,
            },
            "platforms": platforms,
        }

    async def trigger(
        self,
        *,
        sync_task,
        platform: str,
        force: bool,
        request_id: str | None,
        add_task: Callable[..., Any],
    ) -> dict[str, Any]:
        if sync_task is None:
            raise self._error(
                503,
                message="Favorites sync task is not running",
                code="favorites_task_unavailable",
                hint="请确认后端任务已启动后重试",
                request_id=request_id,
            )
        normalized = platform.strip().lower()
        if normalized:
            if normalized not in sync_task.get_supported_platforms():
                raise self._error(
                    400,
                    message=f"Unknown platform: {normalized}",
                    code="unsupported_platform",
                    hint="仅支持 zhihu / xiaohongshu / twitter",
                    request_id=request_id,
                )
            await self.require_manual_policy(
                platform=normalized,
                sync_task=sync_task,
                request_id=request_id,
                force=force,
            )
            run = await sync_task.create_run(
                platform=normalized,
                trigger="manual",
            )
            add_task(
                sync_task.sync_platform_by_name,
                normalized,
                run_id=run["run_id"],
                trigger="manual",
            )
            return {
                "status": "accepted",
                "platform": normalized,
                "run_id": run["run_id"],
            }

        run = await sync_task.create_run(platform=None, trigger="manual")
        add_task(
            sync_task.sync_all_platforms_once,
            run_id=run["run_id"],
            trigger="manual",
        )
        return {
            "status": "accepted",
            "platform": "all",
            "run_id": run["run_id"],
        }

    async def preview(
        self,
        *,
        sync_task,
        platform: str,
        request_id: str | None,
    ) -> FavoritesSyncPreviewResponse | dict[str, Any]:
        if sync_task is None:
            raise self._error(
                503,
                message="Favorites sync task is not running",
                code="favorites_task_unavailable",
                hint="请确认后端任务已启动后重试",
                request_id=request_id,
            )
        normalized = platform.strip().lower()
        if normalized:
            if normalized not in sync_task.get_supported_platforms():
                raise self._error(
                    400,
                    message=f"Unknown platform: {normalized}",
                    code="unsupported_platform",
                    hint="仅支持 zhihu / xiaohongshu / twitter",
                    request_id=request_id,
                )
            preview = await sync_task.preview_platform_by_name(normalized)
            return FavoritesSyncPreviewResponse(
                platform=normalized,
                status=preview.get("status", "unknown"),
                fetched=int(preview.get("fetched") or 0),
                unique=int(preview.get("unique") or 0),
                existing=int(preview.get("existing") or 0),
                estimated_new=int(preview.get("estimated_new") or 0),
                skipped=int(preview.get("skipped") or 0),
                platforms=[preview],
            )
        return await sync_task.preview_all_platforms()

    async def retry_run(
        self,
        *,
        sync_task,
        source_run_id: str,
        request_id: str | None,
        add_task: Callable[..., Any],
    ) -> dict[str, Any]:
        if sync_task is None:
            raise self._error(
                503,
                message="Favorites sync task is not running",
                code="favorites_task_unavailable",
                hint="请确认后端收藏同步任务已启动后重试",
                request_id=request_id,
            )

        recent_runs = await get_recent_task_runs("favorites_sync", limit=20)
        source_run = next(
            (run for run in recent_runs if run.get("run_id") == source_run_id),
            None,
        )
        if source_run is None:
            raise self._error(
                404,
                message=f"Favorites sync run not found: {source_run_id}",
                code="favorites_sync_run_not_found",
                hint="请刷新同步状态后重试",
                request_id=request_id,
            )

        scope = str(source_run.get("scope") or "all").strip().lower()
        platform = None if scope == "all" else scope
        if platform and platform not in sync_task.get_supported_platforms():
            raise self._error(
                400,
                message=f"Unsupported favorites sync scope: {scope}",
                code="unsupported_platform",
                hint="仅支持 zhihu / xiaohongshu / twitter",
                request_id=request_id,
            )
        if platform:
            await self.require_manual_policy(
                platform=platform,
                sync_task=sync_task,
                request_id=request_id,
            )

        run = await sync_task.create_run(
            platform=platform,
            trigger="retry",
            retry_of=source_run_id,
        )
        if platform:
            add_task(
                sync_task.sync_platform_by_name,
                platform,
                run_id=run["run_id"],
                trigger="retry",
            )
        else:
            add_task(
                sync_task.sync_all_platforms_once,
                run_id=run["run_id"],
                trigger="retry",
            )
        return {
            "status": "accepted",
            "platform": platform or "all",
            "run_id": run["run_id"],
            "retry_of": source_run_id,
        }

    async def retry_item(
        self,
        *,
        body: FavoritesSyncItemRetryRequest,
        db: AsyncSession,
        policy_task,
        request_id: str | None,
    ) -> dict[str, Any]:
        platform = body.platform.strip().lower()
        url = body.url.strip()
        if not url:
            raise self._error(
                400,
                message="Favorites item URL is required",
                code="favorites_item_url_required",
                hint="请从失败项中选择带 URL 的记录后重试",
                request_id=request_id,
            )
        if platform not in FavoritesSyncTask.get_fetcher_registry():
            raise self._error(
                400,
                message=f"Unknown platform: {platform}",
                code="unsupported_platform",
                hint="仅支持 zhihu / xiaohongshu / twitter",
                request_id=request_id,
            )
        task = policy_task or self.default_task()
        await self.require_manual_policy(
            platform=platform,
            sync_task=task,
            request_id=request_id,
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
        result = await self.default_task().import_items(
            db,
            platform=platform,
            items=[FavoriteItem(url=url, title=body.title, item_id=body.item_id)],
            source_name=f"favorites_sync:{platform}:retry",
            source_run_id=body.source_run_id,
            retry_run_id=run["run_id"],
            include_item_note=True,
        )
        item_result = result["items"][0]
        if item_result["status"] == "success":
            content_id = item_result["content_id"]
            await record_task_run_success(
                "favorites_sync",
                run["run_id"],
                platform=platform,
                url=url,
                title=body.title,
                item_id=body.item_id,
                source_run_id=body.source_run_id,
                content_id=content_id,
                status="success",
            )
            return {
                "status": "success",
                "platform": platform,
                "run_id": run["run_id"],
                "content_id": content_id,
                "source_run_id": body.source_run_id,
            }

        error = item_result.get("error") or "Favorites item retry failed"
        await record_task_run_error(
            "favorites_sync",
            run["run_id"],
            error,
            platform=platform,
            url=url,
            title=body.title,
            item_id=body.item_id,
            source_run_id=body.source_run_id,
        )
        raise self._error(
            500,
            message=f"Favorites item retry failed: {error}",
            code="favorites_item_retry_failed",
            hint="请确认失败项 URL 仍可访问，或改用整个平台同步重试",
            request_id=request_id,
        )

    async def retry_items(
        self,
        *,
        body: FavoritesSyncItemsRetryRequest,
        db: AsyncSession,
        policy_task,
        request_id: str | None,
    ) -> dict[str, Any]:
        platform = body.platform.strip().lower()
        if platform not in FavoritesSyncTask.get_fetcher_registry():
            raise self._error(
                400,
                message=f"Unknown platform: {platform}",
                code="unsupported_platform",
                hint="仅支持 zhihu / xiaohongshu / twitter",
                request_id=request_id,
            )
        task = policy_task or self.default_task()
        await self.require_manual_policy(
            platform=platform,
            sync_task=task,
            request_id=request_id,
        )
        run = await record_task_run_started(
            "favorites_sync",
            scope=platform,
            trigger="item_batch_retry",
            platform=platform,
            source_run_id=body.source_run_id,
            item_count=len(body.items),
        )
        import_result = await self.default_task().import_items(
            db,
            platform=platform,
            items=[
                FavoriteItem(
                    url=item.url,
                    title=item.title,
                    item_id=item.item_id,
                )
                for item in body.items
            ],
            source_name=f"favorites_sync:{platform}:retry",
            source_run_id=body.source_run_id,
            retry_run_id=run["run_id"],
            retry_mode="batch",
            include_item_note=True,
        )
        status = (
            "success" if import_result["failed"] == 0 else "partial_success"
        )
        await record_task_run_success(
            "favorites_sync",
            run["run_id"],
            platform=platform,
            source_run_id=body.source_run_id,
            status=status,
            imported=import_result["imported"],
            skipped=import_result["skipped"],
            failed=import_result["failed"],
            items=import_result["items"],
            failed_items=import_result["failed_items"],
            failed_items_total=import_result["failed_items_total"],
            failed_items_truncated=import_result["failed_items_truncated"],
        )
        return {
            "status": status,
            "platform": platform,
            "run_id": run["run_id"],
            "source_run_id": body.source_run_id,
            "imported": import_result["imported"],
            "skipped": import_result["skipped"],
            "failed": import_result["failed"],
            "items": import_result["items"],
        }


def get_favorites_sync_service() -> FavoritesSyncService:
    return FavoritesSyncService()
