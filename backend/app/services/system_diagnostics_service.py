"""Read-only system, provider, and background-task diagnostics."""

from __future__ import annotations

from typing import Any

from sqlalchemy import Integer, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import (
    BotConfig,
    Content,
    ContentQueueItem,
    DiscoverySource,
    QueueItemStatus,
    Task,
    TaskStatus,
)
from app.services.background_task_state import (
    get_background_task_states,
    get_recent_task_runs_all,
    get_task_run,
)
from app.services.config_service import ConfigService


class SystemDiagnosticsService:
    def __init__(self, config_service: ConfigService | None = None):
        self.config_service = config_service or ConfigService()

    @staticmethod
    async def _count_by_status(
        db: AsyncSession,
        model,
        status_column,
        enum_cls,
    ) -> dict[str, int]:
        rows = (
            await db.execute(
                select(status_column, func.count())
                .select_from(model)
                .group_by(status_column)
            )
        ).all()
        counts = {item.value: 0 for item in enum_cls}
        for status, count in rows:
            key = status.value if hasattr(status, "value") else str(status)
            counts[key] = int(count or 0)
        return counts

    async def build_background_summary(
        self,
        db: AsyncSession,
    ) -> dict[str, Any]:
        task_counts = await self._count_by_status(
            db,
            Task,
            Task.status,
            TaskStatus,
        )
        queue_counts = await self._count_by_status(
            db,
            ContentQueueItem,
            ContentQueueItem.status,
            QueueItemStatus,
        )
        retryable_distribution = (
            await db.execute(
                select(func.count())
                .select_from(ContentQueueItem)
                .where(ContentQueueItem.status == QueueItemStatus.FAILED)
                .where(ContentQueueItem.attempt_count < ContentQueueItem.max_attempts)
            )
        ).scalar() or 0

        source_stats = (
            await db.execute(
                select(
                    func.count(DiscoverySource.id),
                    func.max(DiscoverySource.last_sync_at),
                    func.sum(
                        func.cast(DiscoverySource.last_error.is_not(None), Integer)
                    ),
                )
            )
        ).one()
        task_states = await get_background_task_states()

        return {
            "parse_tasks": {
                "pending": task_counts.get(TaskStatus.PENDING.value, 0),
                "running": task_counts.get(TaskStatus.RUNNING.value, 0),
                "failed": task_counts.get(TaskStatus.FAILED.value, 0),
                "completed": task_counts.get(TaskStatus.COMPLETED.value, 0),
            },
            "distribution_queue": {
                "scheduled": queue_counts.get(QueueItemStatus.SCHEDULED.value, 0),
                "processing": queue_counts.get(QueueItemStatus.PROCESSING.value, 0),
                "failed": queue_counts.get(QueueItemStatus.FAILED.value, 0),
                "success": queue_counts.get(QueueItemStatus.SUCCESS.value, 0),
                "retryable_failed": int(retryable_distribution),
            },
            "discovery_sync": {
                "source_count": int(source_stats[0] or 0),
                "last_success_at": source_stats[1],
                "last_error_count": int(source_stats[2] or 0),
            },
            "task_states": task_states,
        }

    @staticmethod
    def _serialize_task_state(
        task_name: str,
        state: dict[str, Any],
    ) -> dict[str, Any]:
        known = {
            "task",
            "status",
            "last_started_at",
            "last_success_at",
            "last_error_at",
            "last_error",
            "run_count",
            "error_count",
        }
        return {
            "task": str(state.get("task") or task_name),
            "status": str(state.get("status") or "unknown"),
            "last_started_at": state.get("last_started_at"),
            "last_success_at": state.get("last_success_at"),
            "last_error_at": state.get("last_error_at"),
            "last_error": state.get("last_error"),
            "run_count": int(state.get("run_count") or 0),
            "error_count": int(state.get("error_count") or 0),
            "metrics": {k: v for k, v in state.items() if k not in known},
        }

    async def build_failure_details(
        self,
        db: AsyncSession,
        *,
        limit: int = 20,
    ) -> dict[str, Any]:
        summary = await self.build_background_summary(db)
        task_states_raw = await get_background_task_states()
        task_states = [
            self._serialize_task_state(name, state)
            for name, state in sorted(task_states_raw.items())
        ]
        recent_task_runs = await get_recent_task_runs_all(limit=limit)

        failed_tasks_rows = (
            await db.execute(
                select(Task)
                .where(Task.status == TaskStatus.FAILED)
                .order_by(
                    Task.completed_at.desc().nullslast(),
                    Task.created_at.desc(),
                )
                .limit(limit)
            )
        ).scalars().all()
        failed_parse_tasks = []
        for task in failed_tasks_rows:
            payload = task.payload if isinstance(task.payload, dict) else {}
            content_id_raw = payload.get("content_id")
            failed_parse_tasks.append(
                {
                    "id": task.id,
                    "task_type": task.task_type,
                    "content_id": (
                        int(content_id_raw)
                        if content_id_raw is not None
                        else None
                    ),
                    "retry_count": task.retry_count or 0,
                    "max_retries": task.max_retries or 0,
                    "retryable": (task.retry_count or 0)
                    < (task.max_retries or 0),
                    "last_error": task.last_error,
                    "created_at": task.created_at,
                    "started_at": task.started_at,
                    "completed_at": task.completed_at,
                }
            )

        failed_queue_rows = (
            await db.execute(
                select(ContentQueueItem, Content.title)
                .join(
                    Content,
                    Content.id == ContentQueueItem.content_id,
                    isouter=True,
                )
                .where(ContentQueueItem.status == QueueItemStatus.FAILED)
                .order_by(
                    ContentQueueItem.last_error_at.desc().nullslast(),
                    ContentQueueItem.updated_at.desc(),
                )
                .limit(limit)
            )
        ).all()
        failed_distribution_items = [
            {
                "id": item.id,
                "content_id": item.content_id,
                "title": title,
                "target_platform": item.target_platform,
                "target_id": item.target_id,
                "attempt_count": item.attempt_count or 0,
                "max_attempts": item.max_attempts or 0,
                "retryable": (item.attempt_count or 0)
                < (item.max_attempts or 0),
                "next_attempt_at": item.next_attempt_at,
                "last_error": item.last_error,
                "last_error_type": item.last_error_type,
                "last_error_at": item.last_error_at,
                "updated_at": item.updated_at,
            }
            for item, title in failed_queue_rows
        ]

        failed_sources = (
            await db.execute(
                select(DiscoverySource)
                .where(DiscoverySource.last_error.is_not(None))
                .order_by(
                    DiscoverySource.last_sync_at.desc().nullslast(),
                    DiscoverySource.updated_at.desc(),
                )
                .limit(limit)
            )
        ).scalars().all()
        failed_discovery_sources = [
            {
                "id": source.id,
                "name": source.name,
                "kind": (
                    source.kind.value
                    if hasattr(source.kind, "value")
                    else str(source.kind)
                ),
                "enabled": bool(source.enabled),
                "last_sync_at": source.last_sync_at,
                "last_error": source.last_error,
            }
            for source in failed_sources
        ]

        return {
            "summary": summary,
            "task_states": task_states,
            "recent_task_runs": recent_task_runs,
            "failed_parse_tasks": failed_parse_tasks,
            "failed_distribution_items": failed_distribution_items,
            "failed_discovery_sources": failed_discovery_sources,
        }

    async def build_provider_diagnostics(
        self,
        db: AsyncSession,
    ) -> dict[str, Any]:
        enabled_bot_count = (
            await db.execute(
                select(func.count())
                .select_from(BotConfig)
                .where(BotConfig.enabled == True)  # noqa: E712
            )
        ).scalar() or 0
        ai_config = await self.config_service.get_ai_config()

        return {
            "summary": {
                "configured": bool(ai_config.summary.api_key),
                "enabled": ai_config.summary.enabled,
                "model": ai_config.summary.model,
                "api_version": ai_config.summary.api_version,
            },
            "embedding": {
                "configured": bool(ai_config.embedding.api_key),
                "model": ai_config.embedding.model,
                "output_dimensionality": ai_config.embedding.output_dimensionality,
                "search_max_rows": ai_config.embedding.search_max_rows,
            },
            "agent_chat": {
                "configured": bool(ai_config.agent_chat.api_key),
                "model": ai_config.agent_chat.model,
                "base_url": ai_config.agent_chat.base_url,
            },
            "text_llm": {
                "configured": bool(ai_config.text_llm.api_key),
                "model": ai_config.text_llm.model,
                "base_url": ai_config.text_llm.base_url,
            },
            "vision_llm": {
                "configured": bool(ai_config.vision_llm.api_key),
                "model": ai_config.vision_llm.model,
                "base_url": ai_config.vision_llm.base_url,
            },
            "bots": {"enabled_configs": int(enabled_bot_count)},
        }

    @staticmethod
    async def get_run(run_id: str) -> dict[str, Any] | None:
        return await get_task_run(run_id)

    async def build_metrics_text(self, db: AsyncSession) -> str:
        diagnostics = await self.build_background_summary(db)
        parse = diagnostics["parse_tasks"]
        distribution = diagnostics["distribution_queue"]
        discovery = diagnostics["discovery_sync"]
        lines = [
            "# HELP vaultstream_parse_tasks Number of parse tasks by status.",
            "# TYPE vaultstream_parse_tasks gauge",
            *[
                f'vaultstream_parse_tasks{{status="{status}"}} {count}'
                for status, count in sorted(parse.items())
            ],
            "# HELP vaultstream_distribution_queue Number of distribution queue items by status.",
            "# TYPE vaultstream_distribution_queue gauge",
            *[
                f'vaultstream_distribution_queue{{status="{status}"}} {count}'
                for status, count in sorted(distribution.items())
            ],
            "# HELP vaultstream_discovery_sources Discovery source diagnostics.",
            "# TYPE vaultstream_discovery_sources gauge",
            f'vaultstream_discovery_sources{{state="configured"}} '
            f'{discovery["source_count"]}',
            f'vaultstream_discovery_sources{{state="last_error"}} '
            f'{discovery["last_error_count"]}',
        ]
        return "\n".join(lines) + "\n"


def get_system_diagnostics_service() -> SystemDiagnosticsService:
    return SystemDiagnosticsService()
