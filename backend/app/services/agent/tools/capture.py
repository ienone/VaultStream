from __future__ import annotations

from typing import Any, Dict, Optional

from pydantic import BaseModel, Field, model_validator

from app.models import LayoutType
from app.services.agent.tool_registry import AgentToolContext, AgentToolRegistry
from app.services.content_service import ContentService, ParseQueueUnavailableError


class CaptureContentArgs(BaseModel):
    url: Optional[str] = Field(
        default=None,
        max_length=10_000,
        description="要保存的单个 HTTP/HTTPS 链接；与 text 二选一。",
    )
    text: Optional[str] = Field(
        default=None,
        max_length=200_000,
        description="要保存的原始文字；与 url 二选一。",
    )
    title: Optional[str] = Field(
        default=None,
        max_length=500,
        description="原始文字的标题；链接标题由解析结果确定。",
    )
    note: Optional[str] = Field(default=None, max_length=2000)
    tags: list[str] = Field(default_factory=list, max_length=100)
    layout_type_override: Optional[LayoutType] = None
    is_nsfw: bool = False

    @model_validator(mode="after")
    def _require_exactly_one_capture_input(self):
        has_url = bool((self.url or "").strip())
        has_text = bool((self.text or "").strip())
        if has_url == has_text:
            raise ValueError("Provide exactly one non-empty url or text")
        if has_url and bool((self.title or "").strip()):
            raise ValueError("title is only supported for text captures")
        return self


def register_capture_tool(registry: AgentToolRegistry) -> None:
    registry.register(
        name="capture_content",
        description=(
            "把用户明确指定的一个链接或一段原始文字保存到 VaultStream。"
            "可附加标题、备注、标签和明确的展示模板；不要用它猜测不明确的保存意图。"
        ),
        args_model=CaptureContentArgs,
        result_schema={
            "type": "object",
            "required": [
                "saved",
                "content_id",
                "capture_kind",
                "status",
                "route",
            ],
            "properties": {
                "saved": {"type": "boolean"},
                "content_id": {"type": "integer"},
                "capture_kind": {"type": "string"},
                "status": {"type": "string"},
                "route": {"type": "string"},
            },
        },
        permission_level="write",
        permissions=["content:capture:write"],
        handler=_capture_content_tool,
    )


async def _capture_content_tool(
    args: Dict[str, Any],
    context: AgentToolContext,
) -> Dict[str, Any]:
    session_id = str(context.session_id or "").strip()
    source_name = "telegram_bot" if session_id.startswith("tg-") else "agent"
    client_context = {
        "channel": "telegram_bot" if source_name == "telegram_bot" else "agent",
        "capture_via": "agent",
        "session_id": session_id or None,
        "run_id": context.run_id,
    }
    service = ContentService(context.db)
    url = str(args.get("url") or "").strip()
    text = str(args.get("text") or "").strip()
    common = {
        "tags": list(args.get("tags") or []),
        "source_name": source_name,
        "note": args.get("note"),
        "is_nsfw": bool(args.get("is_nsfw", False)),
        "client_context": client_context,
        "layout_type_override": args.get("layout_type_override"),
    }

    try:
        if url:
            capture_kind = "link"
            content = await service.create_share(url=url, **common)
        else:
            capture_kind = "text"
            content = await service.create_text_capture(
                text,
                title=args.get("title"),
                **common,
            )
        status = content.status.value
        content_id = content.id
    except ParseQueueUnavailableError as error:
        capture_kind = "link"
        content_id = error.content_id
        status = "parse_queue_unavailable"

    return {
        "saved": True,
        "content_id": content_id,
        "capture_kind": capture_kind,
        "status": status,
        "route": f"/collection/{content_id}",
    }
