from __future__ import annotations

from typing import Any, Dict

from sqlalchemy import select

from app.models import BotChat
from app.services.agent.tool_registry import AgentToolContext, AgentToolRegistry


def register_groups_tool(registry: AgentToolRegistry) -> None:
    registry.register(
        name="list_groups",
        description="列出可用推送群组/频道。",
        args_schema={},
        handler=_list_groups_tool,
    )


async def _list_groups_tool(args: Dict[str, Any], context: AgentToolContext) -> Dict[str, Any]:
    rows = (
        await context.db.execute(
            select(BotChat)
            .where(BotChat.enabled == True)  # noqa: E712
            .order_by(BotChat.id.asc())
        )
    ).scalars().all()

    return {
        "count": len(rows),
        "groups": [
            {
                "id": chat.id,
                "chat_id": chat.chat_id,
                "title": chat.title,
                "platform": chat.platform_type,
                "chat_type": chat.chat_type.value if chat.chat_type else None,
                "is_accessible": bool(chat.is_accessible),
            }
            for chat in rows
        ],
    }
