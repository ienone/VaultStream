from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Literal

from sqlalchemy import func, or_, select, update
from sqlalchemy.dialects.sqlite import insert as sqlite_insert

from app.core.db_adapter import AsyncSessionLocal
from app.core.events import event_bus
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.models import NotificationMessage
from app.services.config_service import ConfigService
from app.services.task_run_presentation import build_task_run_presentation, TASK_ERROR_STATUSES, TASK_SUCCESS_STATUSES

NotificationState = Literal["active", "unread", "read", "muted", "snoozed", "all"]

_MANUAL_TRIGGERS = {"manual", "retry", "user", "api"}
_ACCOUNT_LABELS = {
    "bilibili": "哔哩哔哩",
    "xiaohongshu": "小红书",
    "zhihu": "知乎",
    "weibo": "微博",
}



async def record_task_run_notification(run: dict[str, Any]) -> dict[str, Any] | None:
    """Create an inbox receipt for terminal failures and user-triggered successes."""
    notification = build_task_run_notification(run)
    if notification is None:
        return None
    return await record_notification(**notification)


async def record_agent_confirmation_notification(
    confirmation: dict[str, Any],
) -> dict[str, Any]:
    """Expose one durable Agent decision as an actionable inbox item."""
    confirmation_id = str(confirmation.get("id") or "").strip()
    session_id = str(confirmation.get("session_id") or "").strip()
    run_id = str(confirmation.get("run_id") or "").strip()
    tool_name = str(confirmation.get("tool_name") or "Agent 工具").strip()
    if not confirmation_id or not session_id or not run_id:
        raise ValueError("agent confirmation identity is incomplete")

    from_telegram_bot = session_id.startswith("tg-")
    return await record_notification(
        dedupe_key=f"agent-confirmation:{confirmation_id}",
        category="agent",
        severity="attention",
        title=(
            f"Bot 中的 {tool_name} 等待确认"
            if from_telegram_bot
            else f"{tool_name} 等待确认"
        ),
        body=str(confirmation.get("summary") or "Agent 请求执行一项受控操作。")[:1000],
        route=f"/agent?session_id={session_id}",
        source_type=(
            "bot_agent_confirmation"
            if from_telegram_bot
            else "agent_confirmation"
        ),
        source_id=confirmation_id,
        payload={
            "confirmation_id": confirmation_id,
            "session_id": session_id,
            "run_id": run_id,
            "tool_name": tool_name,
            "permission_level": str(confirmation.get("permission_level") or "write"),
            "status": "pending",
            "origin": "telegram_bot" if from_telegram_bot else "vaultstream_app",
        },
        occurred_at=_parse_datetime(confirmation.get("created_at")) or utcnow(),
    )


async def record_bot_capture_notification(
    *,
    content_id: int,
    capture_kind: str,
    display_title: str | None = None,
    display_url: str | None = None,
    client_context: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Project one successfully persisted Telegram capture into the inbox."""
    if content_id <= 0:
        raise ValueError("content_id must be positive")

    normalized_kind = capture_kind.strip().lower()
    labels = {
        "link": "链接",
        "text": "文字",
        "attachment": "附件",
    }
    label = labels.get(normalized_kind, "内容")
    context = client_context if isinstance(client_context, dict) else {}
    source_context = {
        key: context[key]
        for key in ("chat_id", "message_id", "media_group_id", "attachment_type")
        if key in context and isinstance(context[key], (str, int, bool))
    }
    body = str(display_title or display_url or "已保存到 VaultStream").strip()
    return await record_notification(
        dedupe_key=f"bot-capture:{content_id}",
        category="capture",
        severity="info",
        title=f"Telegram {label}已保存",
        body=body[:1000],
        route=f"/collection/{content_id}",
        source_type="bot_capture_receipt",
        source_id=str(content_id),
        payload={
            "content_id": content_id,
            "capture_kind": normalized_kind or "content",
            "origin": "telegram_bot",
            "status": "saved",
            "source_context": source_context,
        },
        expires_at=utcnow() + timedelta(days=30),
    )


async def safely_record_bot_capture_notification(
    **kwargs: Any,
) -> dict[str, Any] | None:
    """Keep inbox projection failures from changing a successful capture."""
    try:
        return await record_bot_capture_notification(**kwargs)
    except Exception as error:
        logger.bind(
            component="notification_inbox",
            content_id=kwargs.get("content_id"),
        ).warning("Bot 捕获回执写入失败，不影响已保存内容: {}", error)
        return None


async def resolve_bot_capture_notification(
    content_id: int,
) -> dict[str, Any] | None:
    """Remove a capture receipt after its content no longer exists."""
    return await _resolve_notification(
        f"bot-capture:{content_id}",
        status="content_deleted",
    )


async def safely_resolve_bot_capture_notification(
    content_id: int,
) -> dict[str, Any] | None:
    try:
        return await resolve_bot_capture_notification(content_id)
    except Exception as error:
        logger.bind(
            component="notification_inbox",
            content_id=content_id,
        ).warning("Bot 捕获回执关闭失败，不影响内容删除: {}", error)
        return None


async def resolve_agent_confirmation_notification(
    confirmation_id: str,
    *,
    status: str,
) -> dict[str, Any] | None:
    """Remove a decided or cancelled confirmation from the active inbox."""
    return await _resolve_notification(
        f"agent-confirmation:{confirmation_id}",
        status=status,
    )


async def sync_account_auth_notification(
    platform: str,
    *,
    is_valid: bool,
    configured: bool | None = None,
) -> dict[str, Any] | None:
    """Project an authoritative platform credential check into the inbox."""
    normalized = platform.strip().lower()
    if not normalized:
        raise ValueError("platform is required")

    if configured is None:
        configured = bool(
            await ConfigService().get_platform_cookie_string(normalized, fresh=True)
        )
    if not configured:
        status = "not_configured"
    else:
        status = "valid" if is_valid else "invalid"
    dedupe_key = f"account-auth:{normalized}"

    async with AsyncSessionLocal() as db:
        row = (
            await db.execute(
                select(NotificationMessage).where(
                    NotificationMessage.dedupe_key == dedupe_key
                )
            )
        ).scalar_one_or_none()

    if status != "invalid":
        if row is None:
            return None
        return await _resolve_notification(dedupe_key, status=status)

    existing_payload = row.payload if row is not None and isinstance(row.payload, dict) else {}
    if existing_payload.get("status") == "invalid":
        return serialize_notification(row)

    label = _ACCOUNT_LABELS.get(normalized, normalized)
    return await record_notification(
        dedupe_key=dedupe_key,
        category="account",
        severity="attention",
        title=f"{label}登录已失效",
        body="VaultStream 保存的登录凭据已无法通过平台校验，请重新登录。",
        route="/accounts",
        source_type="platform_auth",
        source_id=normalized,
        payload={"platform": normalized, "status": "invalid"},
    )


async def safely_sync_account_auth_notification(
    platform: str,
    *,
    is_valid: bool,
    configured: bool | None = None,
) -> dict[str, Any] | None:
    """Keep inbox projection failures from changing the auth operation result."""
    try:
        return await sync_account_auth_notification(
            platform,
            is_valid=is_valid,
            configured=configured,
        )
    except Exception as error:
        logger.bind(
            component="notification_inbox",
            platform=platform,
        ).warning("账号状态通知写入失败，不影响认证结果: {}", error)
        return None


async def _resolve_notification(
    dedupe_key: str,
    *,
    status: str,
) -> dict[str, Any] | None:
    now = utcnow()
    async with AsyncSessionLocal() as db:
        row = (
            await db.execute(
                select(NotificationMessage).where(
                    NotificationMessage.dedupe_key == dedupe_key
                )
            )
        ).scalar_one_or_none()
        if row is None:
            return None
        payload = row.payload if isinstance(row.payload, dict) else {}
        if payload.get("status") == status and row.dismissed_at is not None:
            return serialize_notification(row, now=now)
        row.payload = {
            **payload,
            "status": status,
        }
        row.read_at = row.read_at or now
        row.dismissed_at = now
        row.updated_at = now
        await db.commit()
        await db.refresh(row)

    serialized = serialize_notification(row, now=now)
    await _publish_notification_update(_notification_event_payload(serialized))
    return serialized


def build_task_run_notification(run: dict[str, Any]) -> dict[str, Any] | None:
    """Build a notification input shared by live writes and schema backfill."""
    status = str(run.get("status") or "").lower()
    trigger = str(run.get("trigger") or "").lower()
    is_error = status in TASK_ERROR_STATUSES
    if not is_error and not (status in TASK_SUCCESS_STATUSES and trigger in _MANUAL_TRIGGERS):
        return None

    run_id = str(run.get("run_id") or "").strip()
    task = str(run.get("task") or "background_task").strip()
    metadata = _task_metadata(run)
    result = run.get("result") if isinstance(run.get("result"), dict) else None
    presentation = build_task_run_presentation({**run, "metadata": metadata})
    label = presentation["title"]
    body = presentation["summary"][:1000]
    if is_error:
        dedupe_key = _task_error_dedupe_key(task, metadata)
        title = f"{label}失败"
        severity = "attention"
        expires_at = None
    else:
        dedupe_key = f"task-run:{run_id}"
        title = f"{label}已完成"
        severity = "info"
        expires_at = utcnow() + timedelta(days=30)

    return {
        "dedupe_key": dedupe_key,
        "category": "task",
        "severity": severity,
        "title": title,
        "body": body,
        "route": f"/tasks/{run_id}" if run_id else None,
        "source_type": "background_task_run",
        "source_id": run_id or None,
        "payload": {
            "run_id": run_id,
            "task": task,
            "status": status,
            "metadata": metadata,
            "result": result,
        },
        "occurred_at": _parse_datetime(run.get("finished_at")) or utcnow(),
        "expires_at": expires_at,
    }


async def record_notification(
    *,
    dedupe_key: str,
    category: str,
    severity: str,
    title: str,
    body: str | None,
    route: str | None,
    source_type: str,
    source_id: str | None = None,
    payload: dict[str, Any] | None = None,
    occurred_at: datetime | None = None,
    expires_at: datetime | None = None,
) -> dict[str, Any]:
    now = utcnow()
    occurred = occurred_at or now
    values = {
        "dedupe_key": dedupe_key,
        "category": category,
        "severity": severity,
        "title": title,
        "body": body,
        "route": route,
        "source_type": source_type,
        "source_id": source_id,
        "payload": payload or {},
        "occurrence_count": 1,
        "first_occurred_at": occurred,
        "last_occurred_at": occurred,
        "read_at": None,
        "muted_at": None,
        "snoozed_until": None,
        "expires_at": expires_at,
        "dismissed_at": None,
        "created_at": now,
        "updated_at": now,
    }
    statement = sqlite_insert(NotificationMessage).values(**values)
    statement = statement.on_conflict_do_update(
        index_elements=[NotificationMessage.dedupe_key],
        set_={
            "category": category,
            "severity": severity,
            "title": title,
            "body": body,
            "route": route,
            "source_type": source_type,
            "source_id": source_id,
            "payload": payload or {},
            "occurrence_count": NotificationMessage.occurrence_count + 1,
            "last_occurred_at": occurred,
            "read_at": None,
            "expires_at": expires_at,
            "dismissed_at": None,
            "updated_at": now,
        },
    )
    async with AsyncSessionLocal() as db:
        async with db.begin():
            await db.execute(statement)
        row = (
            await db.execute(
                select(NotificationMessage).where(
                    NotificationMessage.dedupe_key == dedupe_key
                )
            )
        ).scalar_one()
    serialized = serialize_notification(row, now=now)
    await _publish_notification_update(_notification_event_payload(serialized))
    return serialized


async def list_notifications(
    *,
    category: str | None = None,
    state: NotificationState = "active",
    limit: int = 50,
    offset: int = 0,
) -> dict[str, Any]:
    now = utcnow()
    conditions = []
    if category:
        conditions.append(NotificationMessage.category == category)
    conditions.extend(_state_conditions(state, now))

    async with AsyncSessionLocal() as db:
        query = select(NotificationMessage)
        count_query = select(func.count(NotificationMessage.id))
        if conditions:
            query = query.where(*conditions)
            count_query = count_query.where(*conditions)
        rows = (
            await db.execute(
                query.order_by(NotificationMessage.last_occurred_at.desc())
                .offset(offset)
                .limit(limit)
            )
        ).scalars().all()
        total = int((await db.execute(count_query)).scalar() or 0)
        unread_count = int(
            (
                await db.execute(
                    select(func.count(NotificationMessage.id)).where(
                        *_unread_conditions(now)
                    )
                )
            ).scalar()
            or 0
        )
    return {
        "items": [serialize_notification(row, now=now) for row in rows],
        "total": total,
        "unread_count": unread_count,
    }


async def apply_notification_action(
    notification_id: int,
    *,
    action: str,
    snoozed_until: datetime | None = None,
) -> dict[str, Any] | None:
    now = utcnow()
    updates: dict[str, Any]
    if action == "read":
        updates = {"read_at": now}
    elif action == "unread":
        updates = {"read_at": None}
    elif action == "mute":
        updates = {"muted_at": now, "read_at": now}
    elif action == "unmute":
        updates = {"muted_at": None}
    elif action == "snooze":
        normalized_snooze = _parse_datetime(snoozed_until)
        if normalized_snooze is None or normalized_snooze <= now:
            raise ValueError("snoozed_until must be in the future")
        updates = {"snoozed_until": normalized_snooze, "read_at": now}
    elif action == "unsnooze":
        updates = {"snoozed_until": None}
    elif action == "dismiss":
        updates = {"dismissed_at": now, "read_at": now}
    elif action == "restore":
        updates = {"dismissed_at": None}
    else:
        raise ValueError(f"unsupported notification action: {action}")
    updates["updated_at"] = now

    async with AsyncSessionLocal() as db:
        async with db.begin():
            result = await db.execute(
                update(NotificationMessage)
                .where(NotificationMessage.id == notification_id)
                .values(**updates)
            )
        if not result.rowcount:
            return None
        row = await db.get(NotificationMessage, notification_id)
    if row is None:
        return None
    serialized = serialize_notification(row, now=now)
    await _publish_notification_update(_notification_event_payload(serialized))
    return serialized


async def mark_all_notifications_read() -> int:
    now = utcnow()
    async with AsyncSessionLocal() as db:
        async with db.begin():
            result = await db.execute(
                update(NotificationMessage)
                .where(*_unread_conditions(now))
                .values(read_at=now, updated_at=now)
            )
    changed = int(result.rowcount or 0)
    if changed:
        await _publish_notification_update({"read_all": True, "changed": changed})
    return changed


def serialize_notification(
    row: NotificationMessage,
    *,
    now: datetime | None = None,
) -> dict[str, Any]:
    reference = now or utcnow()
    is_snoozed = row.snoozed_until is not None and row.snoozed_until > reference
    is_expired = row.expires_at is not None and row.expires_at <= reference
    return {
        "id": row.id,
        "dedupe_key": row.dedupe_key,
        "category": row.category,
        "severity": row.severity,
        "title": row.title,
        "body": row.body,
        "route": row.route,
        "source_type": row.source_type,
        "source_id": row.source_id,
        "payload": row.payload if isinstance(row.payload, dict) else {},
        "occurrence_count": row.occurrence_count,
        "first_occurred_at": row.first_occurred_at,
        "last_occurred_at": row.last_occurred_at,
        "read_at": row.read_at,
        "muted_at": row.muted_at,
        "snoozed_until": row.snoozed_until,
        "expires_at": row.expires_at,
        "dismissed_at": row.dismissed_at,
        "is_unread": (
            row.read_at is None
            and row.muted_at is None
            and row.dismissed_at is None
            and not is_snoozed
            and not is_expired
        ),
    }


def _state_conditions(state: NotificationState, now: datetime) -> list[Any]:
    if state == "all":
        return []
    active = [
        NotificationMessage.dismissed_at.is_(None),
        or_(NotificationMessage.expires_at.is_(None), NotificationMessage.expires_at > now),
    ]
    if state == "active":
        return active
    if state == "unread":
        return _unread_conditions(now)
    if state == "read":
        return [*active, NotificationMessage.read_at.is_not(None)]
    if state == "muted":
        return [*active, NotificationMessage.muted_at.is_not(None)]
    if state == "snoozed":
        return [*active, NotificationMessage.snoozed_until > now]
    raise ValueError(f"unsupported notification state: {state}")


def _unread_conditions(now: datetime) -> list[Any]:
    return [
        NotificationMessage.read_at.is_(None),
        NotificationMessage.muted_at.is_(None),
        NotificationMessage.dismissed_at.is_(None),
        or_(NotificationMessage.snoozed_until.is_(None), NotificationMessage.snoozed_until <= now),
        or_(NotificationMessage.expires_at.is_(None), NotificationMessage.expires_at > now),
    ]


def _task_metadata(run: dict[str, Any]) -> dict[str, Any]:
    known = {
        "run_id",
        "task",
        "status",
        "started_at",
        "finished_at",
        "error",
        "result",
        "presentation",
    }
    return {key: value for key, value in run.items() if key not in known}


def _task_error_dedupe_key(
    task: str,
    metadata: dict[str, Any],
) -> str:
    dimensions = []
    for key in ("content_id", "source_id", "embedding_id", "queue_item_id", "platform", "target_id"):
        value = metadata.get(key)
        if value is not None and str(value).strip():
            dimensions.append(f"{key}={value}")
        if len(dimensions) == 2:
            break
    suffix = ":".join(dimensions) if dimensions else "general"
    return f"task-error:{task}:{suffix}"[:255]


def _parse_datetime(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        return (
            value.astimezone(timezone.utc).replace(tzinfo=None)
            if value.tzinfo is not None
            else value
        )
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    return (
        parsed.astimezone(timezone.utc).replace(tzinfo=None)
        if parsed.tzinfo is not None
        else parsed
    )


def _notification_event_payload(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "notification_id": item["id"],
        "category": item["category"],
        "severity": item["severity"],
        "is_unread": item["is_unread"],
    }


async def _publish_notification_update(payload: dict[str, Any]) -> None:
    try:
        await event_bus.publish("notification_updated", payload)
    except Exception as error:
        logger.bind(component="notification_inbox").warning(
            "通知更新事件发布失败: {}",
            error,
        )
