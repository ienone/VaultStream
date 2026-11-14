from __future__ import annotations

import asyncio

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models import Content, Task, TaskStatus
from app.core.database import AsyncSessionLocal
from app.core.queue import task_queue
from app.core.events import event_bus
from sqlalchemy import select, update
from app.services.automation_policy import AutomationPolicyService
from app.services.config_service import coerce_bool
from app.services import settings_service


class PostIngestService:
    """Shared post-ingest hooks for parsed, discovered, and imported content."""

    async def run_for_content(
        self, session: AsyncSession, content: Content, *, source: str,
        summary: bool = True, embedding: bool = True, distribution: bool = True,
        scoring: bool = False,
        commit: bool = True,
    ) -> None:
        # Serialize pending-job coalescing with content writes. Running work is
        # not coalesced: a newly changed body needs its own subsequent processing.
        await session.execute(update(Content).where(Content.id == content.id).values(updated_at=Content.updated_at))
        for kind, enabled, priority in (("content_scoring", scoring, 3),
                                        ("content_summary", summary, 2),
                                        ("content_distribution", distribution, 1),
                                        ("content_embedding", embedding, 0)):
            if not enabled:
                continue
            pending = await session.scalar(select(Task.id).where(
                Task.task_type == kind, Task.status == TaskStatus.PENDING,
                Task.payload["content_id"].as_integer() == content.id,
            ).limit(1))
            if pending is None:
                task_queue.add(session, kind, {"content_id": content.id, "source": source, "trigger": "auto", "priority": priority})
        if commit:
            await session.commit()

    async def generate_summary(self, session: AsyncSession, content: Content) -> dict:
        enable_auto_summary = coerce_bool(
            await settings_service.get_setting_value(
                "enable_auto_summary", settings.enable_auto_summary,
            ),
            default=settings.enable_auto_summary,
        )
        if not enable_auto_summary:
            return {"skipped": True, "reason": "automatic_summary_disabled"}

        from app.services.content_summary_service import generate_summary_for_content

        result = await generate_summary_for_content(session, content.id)
        return {"summary_present": bool(result.summary)}

    async def auto_approve_and_enqueue(self, session: AsyncSession, content: Content) -> None:
        from app.services.distribution_topics import tag_distribution_topics
        from app.services.distribution import DistributionService

        await tag_distribution_topics(session, content)
        await DistributionService(session).enqueue_content(content.id, auto_approve=True)


async def process_content_task(task: Task) -> None:
    """一次执行一个后处理阶段；失败不回退正文，也不重放其他阶段。"""
    from app.services.background_task_state import record_task_run_started, record_task_run_success, record_task_run_error

    data = task.payload
    content_id = data["content_id"]
    run_name = data["run_name"]
    run_id = data["run_id"]
    await record_task_run_started(run_name, run_id=run_id, content_id=content_id, task_db_id=task.id)

    async def execute() -> dict:
        async with AsyncSessionLocal() as db:
            content = await db.get(Content, content_id)
            if content is None or content.deleted_at is not None:
                return {"skipped": True, "reason": "content_deleted"}
            pipeline = PostIngestService()
            if task.task_type == "content_scoring":
                from app.models import DiscoveryState
                from app.core.time_utils import utcnow
                from app.services.patrol_service import PatrolService
                decision = await AutomationPolicyService().discovery_scoring()
                if not decision.allowed:
                    return {"skipped": True, "reason": decision.code}
                if content.discovery_state != DiscoveryState.INGESTED or (content.expire_at and content.expire_at < utcnow()):
                    return {"skipped": True, "reason": "not_pending_discovery"}
                profile = await settings_service.get_setting_value("discovery_interest_profile", "")
                if not await PatrolService().score_item(content, str(profile or ""), db=db):
                    raise ValueError("内容评分失败，请检查模型配置后重试")
            elif task.task_type == "content_summary":
                return await pipeline.generate_summary(db, content)
            elif task.task_type == "content_distribution":
                await pipeline.auto_approve_and_enqueue(db, content)
            elif task.task_type == "content_embedding":
                decision = await AutomationPolicyService().automatic_semantic_indexing()
                if not decision.allowed:
                    return {"skipped": True, "reason": decision.code}
                from app.services.embedding_service import EmbeddingService
                await db.rollback()
                return {"indexed": await EmbeddingService().index_content(content_id)}
        return {}

    try:
        result = await asyncio.wait_for(execute(), timeout=task_queue.EXECUTION_TIMEOUT.total_seconds())
        if not await task_queue.mark_complete(task):
            raise RuntimeError("content task already settled")
        await record_task_run_success(run_name, run_id, content_id=content_id, **{
            key: value for key, value in result.items() if key != "content_id"
        })
    except (Exception, asyncio.CancelledError) as error:
        await task_queue.mark_failed(task, reason=str(error) or "Task cancelled")
        await record_task_run_error(run_name, run_id, str(error) or "Task cancelled", content_id=content_id)
        if isinstance(error, asyncio.CancelledError):
            raise
    finally:
        await event_bus.publish("content_updated", {"id": content_id})
