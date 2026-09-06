"""Evidence-backed activity digests for the persistent notification inbox."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import func, select

from app.core.db_adapter import AsyncSessionLocal
from app.core.time_utils import utcnow
from app.models import (
    Content,
    DiscoveryState,
    KnowledgeEvent,
    KnowledgeEventMember,
    KnowledgeEventStatus,
)
from app.services.config_service import ConfigService, coerce_bool, coerce_int
from app.services.notification_inbox import record_notification


_DEFAULT_INTERVAL_HOURS = 24
_MIN_INTERVAL_HOURS = 1
_MAX_INTERVAL_HOURS = 24 * 7
_DIGEST_ITEM_LIMIT = 3
_VISIBLE_DISCOVERY_STATES = (
    DiscoveryState.INGESTED,
    DiscoveryState.SCORED,
    DiscoveryState.VISIBLE,
)


@dataclass(frozen=True, slots=True)
class NotificationDigestConfig:
    enabled: bool
    interval_hours: int
    last_checked_at: datetime | None


async def get_notification_digest_config(
    config_service: ConfigService | None = None,
    *,
    fresh: bool = True,
) -> NotificationDigestConfig:
    config = config_service or ConfigService()
    read = config.get_value_fresh if fresh else config.get_value
    enabled = coerce_bool(await read("enable_notification_digest", False))
    interval_hours = coerce_int(
        await read("notification_digest_interval_hours", _DEFAULT_INTERVAL_HOURS),
        _DEFAULT_INTERVAL_HOURS,
    )
    interval_hours = min(
        max(interval_hours, _MIN_INTERVAL_HOURS),
        _MAX_INTERVAL_HOURS,
    )
    return NotificationDigestConfig(
        enabled=enabled,
        interval_hours=interval_hours,
        last_checked_at=_parse_datetime(
            await read("notification_digest_last_checked_at", None)
        ),
    )


async def create_activity_digest(
    *,
    now: datetime | None = None,
    config_service: ConfigService | None = None,
) -> dict[str, Any]:
    """Create one deterministic digest from persisted discovery and event facts."""
    ended_at = now or utcnow()
    config = config_service or ConfigService()
    digest_config = await get_notification_digest_config(config, fresh=True)
    started_at = digest_config.last_checked_at or (
        ended_at - timedelta(hours=digest_config.interval_hours)
    )
    if started_at >= ended_at:
        started_at = ended_at - timedelta(hours=digest_config.interval_hours)

    discovery_time = func.coalesce(Content.discovered_at, Content.created_at)
    member_count = (
        select(func.count(KnowledgeEventMember.id))
        .where(KnowledgeEventMember.event_id == KnowledgeEvent.id)
        .correlate(KnowledgeEvent)
        .scalar_subquery()
    )
    async with AsyncSessionLocal() as db:
        discovery_filters = (
            Content.deleted_at.is_(None),
            Content.discovery_state.in_(_VISIBLE_DISCOVERY_STATES),
            discovery_time > started_at,
            discovery_time <= ended_at,
        )
        discovery_count = int(
            (
                await db.execute(
                    select(func.count(Content.id)).where(*discovery_filters)
                )
            ).scalar()
            or 0
        )
        discovery_rows = (
            await db.execute(
                select(
                    Content.id,
                    Content.title,
                    Content.source_type,
                    discovery_time.label("occurred_at"),
                )
                .where(*discovery_filters)
                .order_by(discovery_time.desc(), Content.id.desc())
                .limit(_DIGEST_ITEM_LIMIT)
            )
        ).all()

        event_filters = (
            KnowledgeEvent.status == KnowledgeEventStatus.ACTIVE,
            KnowledgeEvent.updated_at > started_at,
            KnowledgeEvent.updated_at <= ended_at,
        )
        event_count = int(
            (
                await db.execute(
                    select(func.count(KnowledgeEvent.id)).where(*event_filters)
                )
            ).scalar()
            or 0
        )
        event_rows = (
            await db.execute(
                select(
                    KnowledgeEvent.id,
                    KnowledgeEvent.title,
                    KnowledgeEvent.updated_at,
                    member_count.label("member_count"),
                )
                .where(*event_filters)
                .order_by(KnowledgeEvent.updated_at.desc(), KnowledgeEvent.id.desc())
                .limit(_DIGEST_ITEM_LIMIT)
            )
        ).all()

    discovery_items = [
        {
            "id": row.id,
            "title": _display_title(row.title, "未命名动态"),
            "source_type": row.source_type,
            "occurred_at": _isoformat(row.occurred_at),
            "route": f"/collection/{row.id}",
        }
        for row in discovery_rows
    ]
    event_items = [
        {
            "id": row.id,
            "title": _display_title(row.title, "未命名事件"),
            "member_count": int(row.member_count or 0),
            "occurred_at": _isoformat(row.updated_at),
            "route": f"/events/{row.id}",
        }
        for row in event_rows
    ]

    notification = None
    if discovery_count or event_count:
        total = discovery_count + event_count
        notification = await record_notification(
            dedupe_key=f"activity-digest:{started_at.isoformat(timespec='microseconds')}",
            category="digest",
            severity="info",
            title=_digest_title(discovery_count, event_count),
            body=_digest_body(
                discovery_count,
                event_count,
                discovery_items,
                event_items,
            ),
            route="/home",
            source_type="activity_digest",
            source_id=started_at.isoformat(timespec="microseconds"),
            payload={
                "window_started_at": _isoformat(started_at),
                "window_ended_at": _isoformat(ended_at),
                "discovery_count": discovery_count,
                "event_count": event_count,
                "total_count": total,
                "discovery_items": discovery_items,
                "event_items": event_items,
                "generated_from": "persisted_activity",
            },
            occurred_at=ended_at,
            expires_at=ended_at + timedelta(days=30),
        )

    await config.set_value(
        "notification_digest_last_checked_at",
        ended_at.isoformat(timespec="microseconds"),
        category="notifications",
        description="周期摘要最近一次完成检查的 UTC 时间",
    )
    return {
        "created": notification is not None,
        "window_started_at": started_at,
        "window_ended_at": ended_at,
        "discovery_count": discovery_count,
        "event_count": event_count,
        "notification": notification,
    }


def _digest_title(discovery_count: int, event_count: int) -> str:
    parts = []
    if discovery_count:
        parts.append(f"{discovery_count} 条动态")
    if event_count:
        parts.append(f"{event_count} 个事件更新")
    return f"周期摘要：{'，'.join(parts)}"


def _digest_body(
    discovery_count: int,
    event_count: int,
    discovery_items: list[dict[str, Any]],
    event_items: list[dict[str, Any]],
) -> str:
    summary = f"本周期收到 {discovery_count} 条动态候选，{event_count} 个事件发生变化。"
    titles = [
        *(item["title"] for item in event_items),
        *(item["title"] for item in discovery_items),
    ][:_DIGEST_ITEM_LIMIT]
    if not titles:
        return summary
    return f"{summary} 最近更新：{'；'.join(titles)}。"


def _display_title(value: Any, fallback: str) -> str:
    title = " ".join(str(value or "").split()).strip()
    return title[:160] if title else fallback


def _parse_datetime(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        parsed = value
    elif not isinstance(value, str) or not value.strip():
        return None
    else:
        try:
            parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
        except ValueError:
            return None
    if parsed.tzinfo is not None:
        return parsed.astimezone(timezone.utc).replace(tzinfo=None)
    return parsed


def _isoformat(value: datetime | None) -> str | None:
    return value.isoformat(timespec="microseconds") if value is not None else None
