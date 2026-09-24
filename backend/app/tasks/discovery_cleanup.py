"""
发现流过期内容清理任务

定期清理过期的发现流内容。
"""
import asyncio

from loguru import logger
from sqlalchemy import delete, exists, select, update
from sqlalchemy.orm import aliased

from app.core.db_adapter import AsyncSessionLocal
from app.core.time_utils import utcnow
from app.core.config import settings
from app.services.settings_service import get_setting_value
from app.services.media_cleanup import cleanup_unreferenced_media
from app.services.background_task_state import (
    record_task_run_error,
    record_task_run_success,
)
from app.models import (
    Content,
    ContentDiscoveryLink,
    ContentQueueItem,
    ContentSource,
    DiscoveryState,
    KnowledgeEventMember,
    PushedRecord,
)


def _has_no_retained_dependency():
    """Return the shared retention predicate for automatic candidate cleanup."""
    child = aliased(Content)
    return (
        Content.parent_id.is_(None)
        & ~exists().where(child.parent_id == Content.id)
        & ~exists().where(KnowledgeEventMember.content_id == Content.id)
        & ~exists().where(ContentSource.content_id == Content.id)
        & ~exists().where(ContentQueueItem.content_id == Content.id)
        & ~exists().where(PushedRecord.content_id == Content.id)
    )


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
                deleted = await self._cleanup_expired()
                async with AsyncSessionLocal() as db:
                    await db.execute(update(Content).where(Content.id == -1).values(id=-1))
                    files, size = await cleanup_unreferenced_media(db)
                    await db.commit()
                if files:
                    logger.info("Discovery media cleanup: removed={} bytes={}", files, size)
                await record_task_run_success("discovery_cleanup", deleted_count=deleted,
                                              removed_media_files=files, freed_media_bytes=size)
            except Exception as e:
                logger.error(f"Discovery cleanup error: {e}")
                await record_task_run_error("discovery_cleanup", None, e)
            await asyncio.sleep(6 * 3600)

    async def _cleanup_expired(self) -> int:
        """Apply configured cleanup policy to expired inbox candidates."""
        cleanup_mode = await get_setting_value(
            "discovery_cleanup_mode",
            settings.discovery_cleanup_mode,
        )
        if cleanup_mode not in {"hard_delete", "expire_only", "archive"}:
            cleanup_mode = settings.discovery_cleanup_mode

        async with AsyncSessionLocal() as db:
            now = utcnow()
            retained_dependency = _has_no_retained_dependency()

            # This first UPDATE acquires SQLite's writer lock before evaluating
            # dependencies and holds it through archive/delete and commit.
            await db.execute(
                update(Content)
                .where(Content.discovery_state.in_([DiscoveryState.VISIBLE, DiscoveryState.INGESTED]))
                .where(Content.expire_at != None)  # noqa: E711
                .where(Content.expire_at < now)
                .where(retained_dependency)
                .values(discovery_state=DiscoveryState.EXPIRED)
            )

            if cleanup_mode == "expire_only":
                await db.commit()
                return 0

            if cleanup_mode == "archive":
                result = await db.execute(
                    update(Content)
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
                    .where(Content.deleted_at == None)  # noqa: E711
                    .where(retained_dependency)
                    .values(
                        deleted_at=now,
                        context_data={
                            "inbox_archived": True,
                            "archive_reason": "discovery_cleanup",
                        },
                    )
                )
                await db.commit()
                archived = int(result.rowcount or 0)
                if archived > 0:
                    logger.info(f"Discovery cleanup: archived {archived} expired items")
                return archived

            # Hard delete expired and old ignored items
            target_ids = (
                await db.execute(
                    select(Content.id)
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
                    .where(retained_dependency)
                )
            ).scalars().all()

            if not target_ids:
                await db.commit()
                return 0

            # Discovery links lack ON DELETE CASCADE. Embeddings/media cascade;
            # saved sources and delivery references were excluded under this lock.
            await db.execute(delete(ContentDiscoveryLink).where(
                ContentDiscoveryLink.content_id.in_(target_ids)
            ))

            result = await db.execute(
                delete(Content).where(Content.id.in_(target_ids))
            )

            await db.commit()

            deleted = result.rowcount
            if deleted > 0:
                logger.info(f"Discovery cleanup: deleted {deleted} expired items")
            return int(deleted or 0)
