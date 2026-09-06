from __future__ import annotations

from typing import Any, Dict, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.models import KnowledgeEventEvidenceState, KnowledgeEventMemberRole
from app.schemas.knowledge_event import KnowledgeEventCreate, KnowledgeEventMemberCreate
from app.services.agent.tool_registry import (
    AgentToolContext,
    AgentToolError,
    AgentToolRegistry,
)
from app.services.knowledge_event_service import KnowledgeEventError, KnowledgeEventService


class OrganizeKnowledgeEventArgs(BaseModel):
    action: Literal["create", "add_member"]
    content_id: int = Field(gt=0)
    event_id: int | None = Field(default=None, gt=0)
    title: str | None = Field(default=None, max_length=240)
    description: str | None = Field(default=None, max_length=4000)
    role: KnowledgeEventMemberRole = KnowledgeEventMemberRole.SOURCE
    evidence_state: KnowledgeEventEvidenceState = (
        KnowledgeEventEvidenceState.UNVERIFIED
    )
    note: str | None = Field(default=None, max_length=2000)

    model_config = ConfigDict(str_strip_whitespace=True)

    @model_validator(mode="after")
    def validate_action_fields(self):
        if self.action == "create":
            if not self.title:
                raise ValueError("title is required when action=create")
            if self.event_id is not None:
                raise ValueError("event_id is not supported when action=create")
        else:
            if self.event_id is None:
                raise ValueError("event_id is required when action=add_member")
            if self.title is not None or self.description is not None:
                raise ValueError(
                    "title and description are only supported when action=create"
                )
        return self


def register_knowledge_event_tool(registry: AgentToolRegistry) -> None:
    registry.register(
        name="organize_knowledge_event",
        description=(
            "在用户明确给出内容和事件边界时创建知识事件，或把一条内容加入已有事件。"
            "必须保留成员角色、证据状态和原内容链接；不要用它自动聚类或猜测合并。"
        ),
        args_model=OrganizeKnowledgeEventArgs,
        result_schema={
            "type": "object",
            "required": [
                "action",
                "event_id",
                "title",
                "member_count",
                "content_id",
                "role",
                "evidence_state",
                "route",
                "items",
                "events",
            ],
            "properties": {
                "action": {"type": "string"},
                "event_id": {"type": "integer"},
                "title": {"type": "string"},
                "member_count": {"type": "integer"},
                "content_id": {"type": "integer"},
                "role": {"type": "string"},
                "evidence_state": {"type": "string"},
                "route": {"type": "string"},
                "items": {"type": "array", "items": {"type": "object"}},
                "events": {"type": "array", "items": {"type": "object"}},
            },
        },
        permission_level="write",
        permissions=["knowledge_events:write"],
        handler=_organize_knowledge_event_tool,
    )


async def _organize_knowledge_event_tool(
    args: Dict[str, Any],
    context: AgentToolContext,
) -> Dict[str, Any]:
    action = str(args["action"])
    content_id = int(args["content_id"])
    member_request = KnowledgeEventMemberCreate(
        content_id=content_id,
        role=args.get("role", KnowledgeEventMemberRole.SOURCE),
        evidence_state=args.get(
            "evidence_state",
            KnowledgeEventEvidenceState.UNVERIFIED,
        ),
        note=args.get("note"),
    )
    service = KnowledgeEventService(context.db)
    try:
        if action == "create":
            event = await service.create_event(
                KnowledgeEventCreate(
                    title=str(args["title"]),
                    description=args.get("description"),
                    members=[member_request],
                ),
                added_by="agent",
            )
        else:
            event = await service.add_member(
                int(args["event_id"]),
                member_request,
                added_by="agent",
            )
    except KnowledgeEventError as error:
        raise AgentToolError(
            error_code=error.code,
            message=error.message,
            retryable=error.status_code == 404,
            details={
                "action": action,
                "event_id": args.get("event_id"),
                "content_id": content_id,
            },
            suggested_fix=(
                "Use existing content and event IDs returned by search_content."
                if error.status_code == 404
                else "Inspect the existing event membership before retrying."
            ),
        ) from error

    member = next(
        item for item in event["members"] if item["content_id"] == content_id
    )
    event_id = int(event["id"])
    event_title = str(event["title"])
    route = f"/events/{event_id}"
    role = _enum_value(member["role"])
    evidence_state = _enum_value(member["evidence_state"])
    content_title = member.get("title") or f"内容 #{content_id}"
    return {
        "action": action,
        "event_id": event_id,
        "title": event_title,
        "member_count": int(event["member_count"]),
        "content_id": content_id,
        "role": role,
        "evidence_state": evidence_state,
        "route": route,
        "items": [
            {
                "kind": "content",
                "content_id": content_id,
                "title": content_title,
                "match_source": "agent_action",
                "source_text": member.get("note") or "知识事件成员内容",
                "route": f"/collection/{content_id}",
            }
        ],
        "events": [
            {
                "kind": "event",
                "event_id": event_id,
                "title": event_title,
                "match_source": "agent_action",
                "source_text": (
                    "由用户确认后创建事件"
                    if action == "create"
                    else "由用户确认后加入事件"
                ),
                "route": route,
            }
        ],
    }


def _enum_value(value: Any) -> str:
    return str(getattr(value, "value", value))
