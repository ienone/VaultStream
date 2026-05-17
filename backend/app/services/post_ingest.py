from __future__ import annotations

import asyncio

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.logging import logger
from app.models import Content
from app.services import settings_service


class PostIngestService:
    """Shared post-ingest hooks for parsed, discovered, and imported content."""

    async def run_for_content(
        self,
        session: AsyncSession,
        content: Content,
        *,
        source: str,
        summary: bool = True,
        embedding: bool = True,
        patrol: bool = False,
        distribution: bool = True,
    ) -> None:
        if summary:
            await self.generate_summary(session, content)
        if embedding:
            self.schedule_embedding_index(content.id)
        if patrol:
            await self.score_discovery(session)
        if distribution:
            await self.auto_approve_and_enqueue(session, content)
        logger.bind(component="post_ingest", source=source, content_id=content.id).info(
            "Post-ingest hooks completed"
        )

    async def generate_summary(self, session: AsyncSession, content: Content) -> None:
        enable_auto_summary = await settings_service.get_setting_value(
            "enable_auto_summary",
            settings.enable_auto_summary,
        )
        if not enable_auto_summary:
            logger.debug("未开启自动摘要生成, 跳过: content_id={}", content.id)
            return

        try:
            from app.services.content_summary_service import generate_summary_for_content

            await generate_summary_for_content(session, content.id)
            logger.info("摘要处理完成: content_id={}, auto_ai={}", content.id, enable_auto_summary)
        except Exception as e:
            logger.warning("摘要生成/处理失败: {}", e)

    def schedule_embedding_index(self, content_id: int) -> None:
        async def _run():
            try:
                from app.services.embedding_service import EmbeddingService
                from app.services.background_task_state import record_task_success

                indexed = await EmbeddingService().index_content(content_id)
                await record_task_success(
                    "embedding_index",
                    content_id=content_id,
                    indexed=bool(indexed),
                )
            except Exception as e:
                from app.services.background_task_state import record_task_error

                logger.bind(component="embedding", content_id=content_id).warning(
                    "语义索引失败(已忽略): {}",
                    e,
                )
                await record_task_error("embedding_index", e, content_id=content_id)

        asyncio.create_task(_run())

    async def score_discovery(self, session: AsyncSession) -> None:
        from app.services.patrol_service import PatrolService

        await PatrolService().score_pending(session)

    async def auto_approve_and_enqueue(self, session: AsyncSession, content: Content) -> None:
        try:
            from app.services.distribution import DistributionService

            await DistributionService(session).auto_approve_if_eligible(content)
        except Exception as e:
            logger.warning("自动审批检查失败: {}", e, exc_info=True)
