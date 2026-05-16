from __future__ import annotations

from typing import Any, Dict

from pydantic import BaseModel, Field
from sqlalchemy import select

from app.models import Content
from app.services.agent.tool_registry import AgentToolContext, AgentToolRegistry
from app.services.content_service import ContentService
from app.utils.tags import normalize_tags


class ManageTagsArgs(BaseModel):
    content_id: int
    add_tags: list[str] = Field(default_factory=list)
    remove_tags: list[str] = Field(default_factory=list)


def register_tags_tool(registry: AgentToolRegistry) -> None:
    registry.register(
        name="manage_tags",
        description="为指定内容添加或移除标签。",
        args_model=ManageTagsArgs,
        result_schema={
            "type": "object",
            "required": ["content_id", "tags", "count"],
            "properties": {
                "content_id": {"type": "integer"},
                "tags": {"type": "array"},
                "count": {"type": "integer"},
            },
        },
        permission_level="write",
        permissions=["content:tags:write"],
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

    service = ContentService(context.db)
    content = await service.update_content(content.id, {"tags": list(lowered_map.values())})

    return {
        "content_id": content.id,
        "tags": content.tags or [],
        "count": len(content.tags or []),
    }
