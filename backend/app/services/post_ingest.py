from __future__ import annotations

import asyncio

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.logging import logger
from app.models import Content
from app.services.automation_policy import AutomationPolicyService
from app.services.config_service import coerce_bool
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
        distribution: bool = True,
    ) -> None:
        content_id = content.id
        if summary:
            await self.generate_summary(session, content)
        try:
            if distribution:
                await self.auto_approve_and_enqueue(session, content)
        finally:
            if embedding:
                # Index after these writes, including when an independent hook fails.
                self.schedule_embedding_index(content_id, source=source)

    async def generate_summary(self, session: AsyncSession, content: Content) -> None:
        enable_auto_summary = coerce_bool(
            await settings_service.get_setting_value(
                "enable_auto_summary", settings.enable_auto_summary,
            ),
            default=settings.enable_auto_summary,
        )
        if not enable_auto_summary:
            return

        try:
            from app.services.content_summary_service import generate_summary_for_content

            await generate_summary_for_content(session, content.id)
        except Exception as e:
            logger.warning("摘要生成/处理失败: {}", e)
            # Summary failures roll back the session and expire this instance.
            # Reload before later hooks read its fields or classify the content.
            await session.refresh(content)

    def schedule_embedding_index(
        self,
        content_id: int,
        *,
        source: str = "post_ingest",
    ) -> asyncio.Task[None]:
        async def _run():
            from app.services.embedding_service import EmbeddingService, EmbeddingIndexError
            try:
                decision = await AutomationPolicyService().automatic_semantic_indexing()
                if decision.allowed:
                    await EmbeddingService().index_content(content_id)
            except EmbeddingIndexError:
                # Each failed unit already has a persisted failure_reason.
                pass
            except Exception as error:
                logger.bind(component="embedding", content_id=content_id).warning(
                    "搜索索引失败: {}", error,
                )

        return asyncio.create_task(_run())

    async def score_discovery(self, session: AsyncSession) -> None:
        decision = await AutomationPolicyService().discovery_scoring()
        if not decision.allowed:
            return

        from app.services.patrol_service import PatrolService

        await PatrolService().score_pending(session)

    async def auto_approve_and_enqueue(self, session: AsyncSession, content: Content) -> None:
        try:
            from app.services.distribution_topics import tag_distribution_topics
            await tag_distribution_topics(session, content)
        except Exception:
            logger.exception("分发主题分类失败: content_id={}", content.id)
        try:
            from app.services.distribution import DistributionService

            await DistributionService(session).auto_approve_if_eligible(content)
        except Exception as e:
            logger.warning("自动审批检查失败: {}", e, exc_info=True)
