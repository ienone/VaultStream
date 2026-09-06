"""Periodic producer for evidence-backed activity digest notifications."""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta

from loguru import logger

from app.core.time_utils import utcnow
from app.services.background_task_state import (
    record_task_error,
    record_task_started,
    record_task_success,
)
from app.services.config_service import ConfigService
from app.services.notification_digest import (
    create_activity_digest,
    get_notification_digest_config,
)


class NotificationDigestTask:
    """Check the persisted digest schedule and emit at most one due digest."""

    def __init__(
        self,
        *,
        config_service: ConfigService | None = None,
        poll_interval_seconds: float = 60,
    ) -> None:
        self._config_service = config_service or ConfigService()
        self._poll_interval_seconds = poll_interval_seconds
        self._task: asyncio.Task | None = None

    def start(self) -> None:
        if self._task and not self._task.done():
            return
        self._task = asyncio.create_task(self._run_loop())
        asyncio.create_task(record_task_started("notification_digest"))

    async def stop(self) -> None:
        if self._task and not self._task.done():
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        self._task = None

    async def run_if_due(self, *, now: datetime | None = None) -> dict | None:
        reference = now or utcnow()
        config = await get_notification_digest_config(
            self._config_service,
            fresh=True,
        )
        if not config.enabled:
            return None
        if (
            config.last_checked_at is not None
            and reference
            < config.last_checked_at + timedelta(hours=config.interval_hours)
        ):
            return None

        result = await create_activity_digest(
            now=reference,
            config_service=self._config_service,
        )
        await record_task_success(
            "notification_digest",
            created=result["created"],
            discovery_count=result["discovery_count"],
            event_count=result["event_count"],
        )
        return result

    async def _run_loop(self) -> None:
        logger.info("Notification digest task started")
        while True:
            try:
                await self.run_if_due()
            except Exception as error:
                logger.exception("Notification digest task failed")
                await record_task_error("notification_digest", error)
            await asyncio.sleep(self._poll_interval_seconds)
