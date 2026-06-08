from __future__ import annotations

import pytest

from app.services.automation_policy import AutomationPolicyService
from app.services.config_service import ConfigService


class _MemoryConfigService(ConfigService):
    def __init__(self, values: dict[str, object]):
        super().__init__(cache={})
        self.values = values

    async def get_value_fresh(self, key: str, default=None):
        return self.values.get(key, default)


@pytest.mark.asyncio
async def test_policy_defaults_keep_existing_automation_enabled():
    policy = AutomationPolicyService(_MemoryConfigService({}))

    assert (await policy.favorites_scheduler()).allowed is True
    assert (await policy.discovery_scoring()).allowed is True
    assert (await policy.distribution_enqueue()).allowed is True
    assert (await policy.cookie_keepalive()).allowed is True


@pytest.mark.asyncio
async def test_policy_blocks_disabled_favorites_platform_without_force():
    policy = AutomationPolicyService(_MemoryConfigService({}))

    blocked = await policy.favorites_platform_manual(
        "zhihu",
        enabled_platforms=[],
    )
    forced = await policy.favorites_platform_manual(
        "zhihu",
        enabled_platforms=[],
        force=True,
    )

    assert blocked.allowed is False
    assert blocked.code == "favorites_platform_disabled"
    assert forced.allowed is True
    assert forced.code == "forced"


@pytest.mark.asyncio
async def test_policy_blocks_paused_distribution_and_disabled_workers():
    policy = AutomationPolicyService(
        _MemoryConfigService(
            {
                "distribution_mode": "paused",
                "enable_cookie_keepalive": "false",
                "enable_favorites_sync_scheduler": False,
                "enable_discovery_patrol": False,
            }
        )
    )

    assert (await policy.distribution_enqueue()).code == "distribution_paused"
    assert (await policy.distribution_worker_poll()).code == "distribution_paused"
    assert (await policy.cookie_keepalive()).code == "cookie_keepalive_disabled"
    assert (await policy.favorites_scheduler()).code == "favorites_scheduler_disabled"
    assert (await policy.discovery_scoring()).code == "discovery_scoring_disabled"
