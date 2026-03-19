from __future__ import annotations

from typing import Any, Dict

from sqlalchemy import select

from app.models import Content
from app.services.agent.tool_registry import AgentToolContext, AgentToolRegistry
from app.utils.tags import normalize_tags


def register_tags_tool(registry: AgentToolRegistry) -> None:
    registry.register(
        name="manage_tags",
        description="为指定内容添加或移除标签。",
        args_schema={
            "content_id": {"type": "integer", "required": True},
            "add_tags": {"type": "array", "required": False, "items": {"type": "string"}},
            "remove_tags": {"type": "array", "required": False, "items": {"type": "string"}},
        },
        handler=_manage_tags_tool,
    )


async def _manage_tags_tool(args: Dict[str, Any], context: AgentToolContext) -> Dict[str, Any]:
    content_id = args.get("content_id")
    if content_id is None:
        raise ValueError("content_id is required")

    content = (
        await context.db.execute(select(Content).where(Content.id == int(content_id)))
    ).scalar_one_or_none()
    if content is None:
        raise ValueError(f"content not found: {content_id}")

    current_tags = normalize_tags(content.tags or [], lower=False)
    lowered_map = {tag.lower(): tag for tag in current_tags}

    add_tags = normalize_tags(args.get("add_tags") or [], lower=False)
    remove_tags = normalize_tags(args.get("remove_tags") or [], lower=True)

    for tag in add_tags:
        lowered_map[tag.lower()] = tag

    for tag in remove_tags:
        lowered_map.pop(tag, None)

    content.tags = list(lowered_map.values())
    await context.db.commit()
    await context.db.refresh(content)

    return {
        "content_id": content.id,
        "tags": content.tags or [],
        "count": len(content.tags or []),
    }
