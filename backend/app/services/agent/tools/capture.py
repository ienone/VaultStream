from __future__ import annotations

import asyncio
from typing import Any, Dict, Optional

from pydantic import BaseModel, Field, model_validator
from sqlalchemy import select

from app.adapters.storage import get_storage_backend
from app.core.config import settings

from app.models import AgentToolCall, Content, LayoutType
from app.services.agent.tool_registry import AgentToolContext, AgentToolError, AgentToolRegistry
from app.services.content_service import ContentService, ParseQueueUnavailableError
from app.services.qq_agent_materials import fetch_attachment, resolve_capture_source


class CaptureContentArgs(BaseModel):
    source_ref: Optional[str] = Field(default=None, max_length=200, description="QQ 入口提供的真实材料引用；与 url/text 三选一。QQ 必须使用该字段。")
    text_selection: Optional[str] = Field(default=None, max_length=200_000, description="仅限 source_ref 指向文字时，从原文逐字选取的连续子串；省略则保存整段原文。")
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
        has_ref = bool((self.source_ref or "").strip())
        if sum((has_url, has_text, has_ref)) != 1:
            raise ValueError("Provide exactly one non-empty url, text or source_ref")
        if self.text_selection is not None and not has_ref:
            raise ValueError("text_selection requires source_ref")
        if has_url and bool((self.title or "").strip()):
            raise ValueError("title is only supported for text captures")
        return self


def register_capture_tool(registry: AgentToolRegistry) -> None:
    registry.register(
        name="capture_content",
        description=(
            "把用户明确指定的一个链接、一段原始文字或 QQ 消息材料保存到 VaultStream。"
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
    if context.qq_sources is not None:
        return await _capture_qq_source(args, context)
    if args.get("source_ref"):
        raise AgentToolError(error_code="qq_capture_origin_required", message="材料引用仅在已授权 QQ 私聊入口可用。")
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


async def _capture_qq_source(args: Dict[str, Any], context: AgentToolContext) -> Dict[str, Any]:
    source = resolve_capture_source(args, context.qq_sources or {})
    # A model may repeat the same call after reading a result. Reuse its persisted
    # successful receipt; a duplicate HTTP delivery reuses the entire run instead.
    calls = (await context.db.execute(select(AgentToolCall).where(
        AgentToolCall.run_id == context.run_id,
        AgentToolCall.tool_name == "capture_content",
        AgentToolCall.status == "completed",
    ))).scalars().all()
    for call in calls:
        if ((call.args or {}).get("source_ref") == args.get("source_ref")
                and (call.args or {}).get("text_selection") == args.get("text_selection")):
            return call.result

    client_context = {**(context.qq_origin or {}), "session_id": context.session_id,
                      "run_id": context.run_id, "source_ref": args["source_ref"],
                      "source_message_id": source["message_id"], "capture_via": "agent",
                      "capture_kind": source["kind"]}
    common = {"tags": list(args.get("tags") or []), "source_name": "qq_bot",
              "note": args.get("note"), "is_nsfw": bool(args.get("is_nsfw", False)),
              "client_context": client_context, "layout_type_override": args.get("layout_type_override")}
    service = ContentService(context.db)
    kind = source["kind"]
    queue_error = False
    try:
        if kind == "link":
            content = await service.create_share(url=source["url"], **common)
        elif kind == "text":
            content = await service.create_text_capture(source["text"], title=args.get("title"), **common)
        else:
            capture_file = await fetch_attachment(source)
            content = await service.create_files_capture([capture_file], storage=get_storage_backend(),
                            max_bytes=max(1, settings.capture_upload_max_bytes), **common)
    except ParseQueueUnavailableError as exc:
        content = await context.db.get(Content, exc.content_id)
        queue_error = True
    content_id = content.id
    # Allow a simple save-and-read request to continue in the same Agent run.
    # Parsing itself stays in the existing durable task queue.
    if kind == "link" and not queue_error:
        for _ in range(15):
            await context.db.refresh(content)
            if content.status.value not in {"unprocessed", "processing"}:
                break
            await context.db.commit()
            await asyncio.sleep(2)
    return {"saved": True, "content_id": content_id, "capture_kind": kind,
            "status": "parse_queue_unavailable" if queue_error else content.status.value,
            "title": content.title, "author": content.author_name,
            "body": (content.body or "")[:4000], "summary": content.summary,
            "url": content.clean_url, "route": f"/collection/{content_id}"}
