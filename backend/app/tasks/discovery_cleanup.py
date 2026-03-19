"""
发现流过期内容清理任务

定期清理过期的发现流内容。
"""
import asyncio

from loguru import logger
from sqlalchemy import delete, update

from app.core.db_adapter import AsyncSessionLocal
from app.core.time_utils import utcnow
from app.models import Content, DiscoveryState


class DiscoveryCleanupTask:
    """发现流过期内容清理任务"""

    def __init__(self):
        self._task: asyncio.Task | None = None

    def start(self):
        if self._task and not self._task.done():
            return
        self._task = asyncio.create_task(self._cleanup_loop())

    async def stop(self):
        if self._task and not self._task.done():
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass

    async def _cleanup_loop(self):
        """Run cleanup every 6 hours"""
        logger.info("Discovery cleanup task started")
        while True:
            try:
                await self._cleanup_expired()
            except Exception as e:
                logger.error(f"Discovery cleanup error: {e}")
            await asyncio.sleep(6 * 3600)

    async def _cleanup_expired(self):
        """Delete contents where expire_at < now and state in (ignored, expired)"""
        async with AsyncSessionLocal() as db:
            now = utcnow()

            # Mark expired visible items
            await db.execute(
                update(Content)
                .where(Content.discovery_state == DiscoveryState.VISIBLE)
                .where(Content.expire_at != None)  # noqa: E711
                .where(Content.expire_at < now)
                .values(discovery_state=DiscoveryState.EXPIRED)
            )

            # Hard delete expired and old ignored items
            result = await db.execute(
                delete(Content)
                .where(
                    Content.discovery_state.in_(
                        [
                            DiscoveryState.EXPIRED,
                            DiscoveryState.IGNORED,
                        ]
                    )
                )
                .where(Content.expire_at != None)  # noqa: E711
                .where(Content.expire_at < now)
            )

            await db.commit()

            deleted = result.rowcount
            if deleted > 0:
                logger.info(f"Discovery cleanup: deleted {deleted} expired items")
