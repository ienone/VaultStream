from __future__ import annotations

from typing import Any, Dict

from pydantic import BaseModel, Field
from sqlalchemy import select

from app.core.time_utils import utcnow
from app.models import ContentQueueItem, QueueItemStatus
from app.services.agent.tool_registry import AgentToolContext, AgentToolRegistry
from app.services.distribution import DistributionService


class PushBatchArgs(BaseModel):
    content_ids: list[int] = Field(min_length=1)
    bot_chat_id: int | None = None
    force_enqueue: bool = True
    include_success: bool = False


def register_push_tool(registry: AgentToolRegistry) -> None:
    registry.register(
        name="push_batch",
        description="将内容批量推送到队列（基于现有规则匹配结果）。",
        args_model=PushBatchArgs,
        result_schema={
            "type": "object",
            "required": ["content_ids", "bot_chat_id", "enqueued_total", "queue_items_total", "scheduled_count", "scheduled_item_ids"],
            "properties": {
                "content_ids": {"type": "array"},
                "bot_chat_id": {"type": ["integer", "null"]},
                "enqueued_total": {"type": "integer"},
                "queue_items_total": {"type": "integer"},
                "scheduled_count": {"type": "integer"},
                "scheduled_item_ids": {"type": "array"},
            },
        },
        permission_level="external_side_effect",
        permissions=["distribution_queue:write", "push:enqueue"],
        handler=_push_batch_tool,
    )


async def _push_batch_tool(args: Dict[str, Any], context: AgentToolContext) -> Dict[str, Any]:
    raw_content_ids = args.get("content_ids")
    if not isinstance(raw_content_ids, list) or not raw_content_ids:
        raise ValueError("content_ids is required")

    content_ids = sorted({int(cid) for cid in raw_content_ids if str(cid).strip()})
    if not content_ids:
        raise ValueError("content_ids is required")

    bot_chat_id = args.get("bot_chat_id")
    bot_chat_id = int(bot_chat_id) if bot_chat_id is not None else None
    force_enqueue = bool(args.get("force_enqueue", True))
    include_success = bool(args.get("include_success", False))

    enqueued_total = 0
    if force_enqueue:
        distribution_service = DistributionService(context.db)
        for content_id in content_ids:
            enqueued_total += await distribution_service.enqueue_content(
                content_id,
                force=False,
            )

    stmt = select(ContentQueueItem).where(ContentQueueItem.content_id.in_(content_ids))
    if bot_chat_id is not None:
        stmt = stmt.where(ContentQueueItem.bot_chat_id == bot_chat_id)
    queue_items = (await context.db.execute(stmt)).scalars().all()

    now = utcnow()
    changed = 0
    changed_ids: list[int] = []

    for item in queue_items:
        if item.status == QueueItemStatus.SUCCESS and not include_success:
            continue

        item.status = QueueItemStatus.SCHEDULED
        item.scheduled_at = now
        item.next_attempt_at = None
        item.last_error = None
        item.last_error_type = None
        item.last_error_at = None
        item.locked_at = None
        item.locked_by = None
        if include_success:
            item.message_id = None
        changed += 1
        changed_ids.append(item.id)

    await context.db.commit()

    return {
        "content_ids": content_ids,
        "bot_chat_id": bot_chat_id,
        "enqueued_total": enqueued_total,
        "queue_items_total": len(queue_items),
        "scheduled_count": changed,
        "scheduled_item_ids": changed_ids,
    }
