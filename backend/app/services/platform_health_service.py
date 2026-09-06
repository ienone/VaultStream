"""Platform login and favorites health aggregation."""

from __future__ import annotations

from typing import Any

from app.adapters.favorites.errors import FavoritesFetchError
from app.core.api_errors import build_error_payload
from app.core.config import settings
from app.core.logging import logger
from app.services.background_task_state import (
    get_recent_task_runs,
)
from app.services.browser_auth_service import browser_auth_service
from app.services.config_service import ConfigService, coerce_bool
from app.services.settings_service import get_setting_value
from app.tasks.favorites_sync import FavoritesSyncTask


class PlatformHealthService:
    def __init__(self, config_service: ConfigService | None = None):
        self.config_service = config_service or ConfigService()

    @staticmethod
    def _platform_label(platform: str) -> str:
        labels = {
            "zhihu": "知乎",
            "xiaohongshu": "小红书",
            "twitter": "Twitter / X",
            "weibo": "微博",
            "bilibili": "Bilibili",
        }
        return labels.get(platform, platform)

    @staticmethod
    def _platform_cookie_keys(platform: str) -> list[str]:
        if platform == "bilibili":
            return ["bilibili_cookie", "bilibili_bili_jct"]
        return [f"{platform}_cookie"]

    async def _is_any_platform_cookie_configured(self, platform: str) -> bool:
        for key in self._platform_cookie_keys(platform):
            value = await get_setting_value(key)
            if isinstance(value, str) and value.strip():
                return True
        return False

    @staticmethod
    def _latest_favorites_run_for_platform(
        runs: list[dict[str, Any]],
        platform: str,
    ) -> dict[str, Any] | None:
        for run in runs:
            scope = str(run.get("scope") or "all").strip().lower()
            if scope == platform or scope == "all":
                return run
        return None

    async def _cookie_keepalive_status(self) -> dict[str, Any]:
        runs: list[dict[str, Any]] = []
        for task_name in (
            "cookie_keepalive_zhihu",
            "cookie_keepalive_xiaohongshu",
            "cookie_keepalive_weibo",
        ):
            for run in await get_recent_task_runs(task_name, limit=5):
                runs.append({"task": task_name, **run})
        runs.sort(
            key=lambda item: str(item.get("started_at") or ""),
            reverse=True,
        )
        recent_failure = next(
            (run for run in runs if str(run.get("status") or "") == "error"),
            None,
        )
        enabled = coerce_bool(
            await get_setting_value(
                "enable_cookie_keepalive",
                settings.enable_cookie_keepalive,
            ),
            settings.enable_cookie_keepalive,
        )
        return {
            "enabled": enabled,
            "recent_run": runs[0] if runs else None,
            "recent_failure": recent_failure,
        }

    async def get_status(
        self,
        *,
        sync_task=None,
        request_id: str | None = None,
    ) -> dict[str, Any]:
        task = sync_task or FavoritesSyncTask(config_service=self.config_service)
        enabled_favorites = await task.load_enabled_platforms()
        recent_runs = await get_recent_task_runs("favorites_sync", limit=20)
        supported_favorites = set(task.get_supported_platforms())
        browser_platforms = set(browser_auth_service.platforms.keys())
        ordered = ["zhihu", "xiaohongshu", "twitter", "weibo", "bilibili"]
        platforms = [
            platform
            for platform in ordered
            + sorted((supported_favorites | browser_platforms) - set(ordered))
            if platform in supported_favorites
            or platform in browser_platforms
            or platform == "bilibili"
        ]

        items: list[dict[str, Any]] = []
        for platform in platforms:
            cookie_configured = await self._is_any_platform_cookie_configured(
                platform
            )
            browser_auth_supported = platform in browser_platforms
            browser_auth_valid: bool | None = None
            browser_auth_error: str | None = None
            if browser_auth_supported and cookie_configured:
                try:
                    browser_auth_valid = (
                        await browser_auth_service.check_platform_status(platform)
                    )
                except Exception as exc:
                    browser_auth_valid = False
                    browser_auth_error = str(exc)
                    logger.warning(
                        "[platform health] browser auth check failed for {}: {}",
                        platform,
                        exc,
                    )

            favorites_supported = platform in supported_favorites
            favorites_enabled = platform in enabled_favorites
            favorites_authenticated: bool | None = None
            favorites_available = favorites_supported
            favorites_error: str | None = None
            favorites_status_error: dict[str, Any] | None = None
            platform_state = (
                await self.config_service.get_favorites_sync_platform_state(
                    platform,
                    default_rate_per_minute=task.default_rate_for(platform),
                )
            )
            favorites_last_result = platform_state.last_result

            if favorites_supported and favorites_enabled:
                fetcher_cls = task.get_fetcher_cls(platform)
                if fetcher_cls is not None:
                    try:
                        favorites_authenticated = await fetcher_cls().check_auth()
                    except ImportError as exc:
                        favorites_available = False
                        favorites_authenticated = False
                        favorites_error = str(exc)
                        favorites_status_error = build_error_payload(
                            message=str(exc),
                            code="dependency_missing",
                            hint="依赖缺失，请检查后端运行环境",
                            request_id=request_id,
                        )
                    except FavoritesFetchError as exc:
                        favorites_available = exc.code != "cli_unavailable"
                        favorites_authenticated = False
                        favorites_error = exc.message
                        favorites_status_error = {
                            "detail": exc.message,
                            **exc.as_dict(),
                            "request_id": request_id,
                        }
                    except Exception as exc:
                        favorites_available = False
                        favorites_authenticated = False
                        favorites_error = str(exc)
                        favorites_status_error = build_error_payload(
                            message=str(exc),
                            code="auth_check_failed",
                            hint="认证检查失败，请稍后重试",
                            request_id=request_id,
                        )
                        logger.warning(
                            "[platform health] favorites auth check failed for {}: {}",
                            platform,
                            exc,
                        )

            latest_run = self._latest_favorites_run_for_platform(
                recent_runs,
                platform,
            )
            issues: list[str] = []
            if (
                browser_auth_supported
                and favorites_enabled
                and not cookie_configured
            ):
                issues.append("未配置登录 Cookie")
            if browser_auth_valid is False:
                issues.append("登录状态不可用")
            if favorites_enabled and favorites_authenticated is False:
                issues.append("收藏同步认证失败")
            if (
                favorites_enabled
                and latest_run
                and latest_run.get("status") == "error"
            ):
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
                    "label": self._platform_label(platform),
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
                        "last_result": (
                            favorites_last_result
                            if isinstance(favorites_last_result, dict)
                            else None
                        ),
                        "last_run": latest_run,
                        "error": favorites_error,
                        "status_error": favorites_status_error,
                    },
                }
            )

        return {
            "platforms": items,
            "recent_favorites_runs": recent_runs[:10],
            "cookie_keepalive": await self._cookie_keepalive_status(),
        }


def get_platform_health_service() -> PlatformHealthService:
    return PlatformHealthService()
