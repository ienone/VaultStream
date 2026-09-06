from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Iterable

from app.core.config import settings
from app.services.config_service import ConfigService, coerce_bool


@dataclass(frozen=True)
class AutomationPolicyDecision:
    allowed: bool
    code: str
    reason: str
    setting_key: str | None = None
    setting_value: Any = None

    def as_dict(self) -> dict[str, Any]:
        return {
            "allowed": self.allowed,
            "code": self.code,
            "reason": self.reason,
            "setting_key": self.setting_key,
            "setting_value": self.setting_value,
        }


class AutomationPolicyService:
    """Centralized policy checks for background automation entrypoints."""

    def __init__(self, config_service: ConfigService | None = None) -> None:
        self._config = config_service or ConfigService()

    async def favorites_scheduler(self) -> AutomationPolicyDecision:
        enabled = coerce_bool(
            await self._config.get_value_fresh(
                "enable_favorites_sync_scheduler",
                getattr(settings, "enable_favorites_sync_scheduler", True),
            )
        )
        if enabled:
            return AutomationPolicyDecision(True, "allowed", "favorites scheduler enabled")
        return AutomationPolicyDecision(
            False,
            "favorites_scheduler_disabled",
            "favorites sync scheduler is disabled",
            "enable_favorites_sync_scheduler",
            enabled,
        )

    async def favorites_platform_manual(
        self,
        platform: str,
        *,
        enabled_platforms: Iterable[str],
        force: bool = False,
    ) -> AutomationPolicyDecision:
        normalized = platform.strip().lower()
        enabled = {item.strip().lower() for item in enabled_platforms}
        if normalized in enabled:
            return AutomationPolicyDecision(True, "allowed", "favorites platform enabled")
        if force:
            return AutomationPolicyDecision(True, "forced", "manual override requested")

        allow_disabled = coerce_bool(
            await self._config.get_value_fresh(
                "allow_manual_favorites_sync_disabled_platform",
                getattr(settings, "allow_manual_favorites_sync_disabled_platform", False),
            )
        )
        if allow_disabled:
            return AutomationPolicyDecision(
                True,
                "allowed_by_policy",
                "disabled favorites platform manual sync allowed by policy",
                "allow_manual_favorites_sync_disabled_platform",
                allow_disabled,
            )
        return AutomationPolicyDecision(
            False,
            "favorites_platform_disabled",
            f"favorites platform is disabled: {normalized}",
            "favorites_sync_platforms",
            sorted(enabled),
        )

    async def discovery_source_manual(
        self,
        *,
        source_enabled: bool,
        force: bool = False,
    ) -> AutomationPolicyDecision:
        if source_enabled:
            return AutomationPolicyDecision(True, "allowed", "discovery source enabled")
        if force:
            return AutomationPolicyDecision(True, "forced", "manual override requested")
        return AutomationPolicyDecision(
            False,
            "discovery_source_disabled",
            "discovery source is disabled",
            "DiscoverySource.enabled",
            source_enabled,
        )

    async def discovery_scoring(self) -> AutomationPolicyDecision:
        patrol_enabled = coerce_bool(
            await self._config.get_value_fresh(
                "enable_discovery_patrol",
                getattr(settings, "enable_discovery_patrol", True),
            )
        )
        scoring_enabled = coerce_bool(
            await self._config.get_value_fresh(
                "enable_ai_scoring",
                getattr(settings, "enable_ai_scoring", True),
            )
        )
        if patrol_enabled and scoring_enabled:
            return AutomationPolicyDecision(True, "allowed", "discovery scoring enabled")
        key = "enable_discovery_patrol" if not patrol_enabled else "enable_ai_scoring"
        value = patrol_enabled if not patrol_enabled else scoring_enabled
        return AutomationPolicyDecision(
            False,
            "discovery_scoring_disabled",
            "discovery scoring is disabled",
            key,
            value,
        )

    async def automatic_semantic_indexing(self) -> AutomationPolicyDecision:
        enabled = coerce_bool(
            await self._config.get_value_fresh(
                "enable_auto_semantic_indexing",
                getattr(settings, "enable_auto_semantic_indexing", True),
            )
        )
        if enabled:
            return AutomationPolicyDecision(
                True,
                "allowed",
                "automatic semantic indexing enabled",
            )
        return AutomationPolicyDecision(
            False,
            "automatic_semantic_indexing_disabled",
            "automatic semantic indexing is disabled",
            "enable_auto_semantic_indexing",
            enabled,
        )

    async def parse_worker_poll(self) -> AutomationPolicyDecision:
        enabled = coerce_bool(
            await self._config.get_value_fresh(
                "enable_parse_worker",
                getattr(settings, "enable_parse_worker", True),
            )
        )
        if enabled:
            return AutomationPolicyDecision(True, "allowed", "parse worker enabled")
        return AutomationPolicyDecision(
            False,
            "parse_worker_disabled",
            "parse worker polling is disabled",
            "enable_parse_worker",
            enabled,
        )

    async def distribution_enqueue(
        self,
        *,
        force: bool = False,
    ) -> AutomationPolicyDecision:
        mode = str(
            await self._config.get_value_fresh(
                "distribution_mode",
                getattr(settings, "distribution_mode", "auto"),
            )
            or "auto"
        ).strip().lower()
        if mode != "paused" or force:
            return AutomationPolicyDecision(True, "allowed", "distribution enqueue allowed")
        return AutomationPolicyDecision(
            False,
            "distribution_paused",
            "distribution mode is paused",
            "distribution_mode",
            mode,
        )

    async def distribution_worker_poll(self) -> AutomationPolicyDecision:
        mode = str(
            await self._config.get_value_fresh(
                "distribution_mode",
                getattr(settings, "distribution_mode", "auto"),
            )
            or "auto"
        ).strip().lower()
        if mode != "paused":
            return AutomationPolicyDecision(True, "allowed", "distribution worker enabled")
        return AutomationPolicyDecision(
            False,
            "distribution_paused",
            "distribution worker polling is paused",
            "distribution_mode",
            mode,
        )

    async def cookie_keepalive(self) -> AutomationPolicyDecision:
        enabled = coerce_bool(
            await self._config.get_value_fresh(
                "enable_cookie_keepalive",
                getattr(settings, "enable_cookie_keepalive", True),
            )
        )
        if enabled:
            return AutomationPolicyDecision(True, "allowed", "cookie keepalive enabled")
        return AutomationPolicyDecision(
            False,
            "cookie_keepalive_disabled",
            "cookie keepalive is disabled",
            "enable_cookie_keepalive",
            enabled,
        )

    async def ingest_mode(self) -> str:
        return str(
            await self._config.get_value_fresh("ingest_mode", getattr(settings, "ingest_mode", "parse"))
            or "parse"
        ).strip().lower()
