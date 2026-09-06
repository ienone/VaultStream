from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional

from pydantic import BaseModel, Field, field_validator

from app.models import Platform
from app.services.agent.tool_registry import AgentToolContext, AgentToolRegistry
from app.services.search_service import UnifiedSearchService


class SearchContentArgs(BaseModel):
    query: str = Field(min_length=1)
    top_k: int = Field(default=10, ge=1, le=100)
    platform: Optional[str] = None
    date_from: Optional[datetime] = None
    date_to: Optional[datetime] = None

    @field_validator("platform")
    @classmethod
    def validate_platform(cls, value: str | None) -> str | None:
        normalized = (value or "").strip().lower()
        if not normalized:
            return None
        valid = {platform.value for platform in Platform}
        if normalized not in valid:
            raise ValueError(f"platform must be one of {sorted(valid)}")
        return normalized


def register_search_tool(registry: AgentToolRegistry) -> None:
    registry.register(
        name="search_content",
        description=(
            "检索内容库、知识事件和音视频时间点，支持按平台和内容创建时间过滤。"
        ),
        args_model=SearchContentArgs,
        result_schema={
            "type": "object",
            "required": [
                "query",
                "top_k",
                "count",
                "items",
                "events",
                "timepoints",
            ],
            "properties": {
                "query": {"type": "string"},
                "top_k": {"type": "integer"},
                "count": {"type": "integer"},
                "items": {
                    "type": "array",
                    "description": "内容证据；route 可在 VaultStream 内定位原文。",
                },
                "events": {
                    "type": "array",
                    "description": "知识事件证据；平台和时间过滤不影响事件。",
                },
                "timepoints": {
                    "type": "array",
                    "description": (
                        "音视频时间点证据；route 可直接定位播放位置。"
                    ),
                },
            },
        },
        permission_level="read",
        permissions=["content:read", "semantic_search:read"],
        handler=_search_content_tool,
    )


def _parse_dt(raw: Any) -> Optional[datetime]:
    if raw is None:
        return None
    if isinstance(raw, datetime):
        return raw
    if isinstance(raw, str) and raw.strip():
        try:
            return datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except Exception:
            return None
    return None


async def _search_content_tool(args: Dict[str, Any], context: AgentToolContext) -> Dict[str, Any]:
    query = str(args.get("query") or "").strip()
    if not query:
        raise ValueError("query is required")

    top_k = int(args.get("top_k") or 10)
    top_k = max(1, min(100, top_k))
    platform = str(args.get("platform") or "").strip().lower() or None
    date_from = _parse_dt(args.get("date_from"))
    date_to = _parse_dt(args.get("date_to"))

    results = await UnifiedSearchService(context.db).search(
        query=query,
        top_k=top_k,
        kind="all",
        content_scope="library",
        platforms=[platform] if platform else None,
        date_from=date_from,
        date_to=date_to,
    )

    items = [
        {
            "kind": "content",
            "content_id": hit.content.id,
            "platform": hit.content.platform.value if hit.content.platform else "",
            "title": hit.content.title,
            "url": hit.content.url,
            "route": f"/collection/{hit.content.id}",
            "score": float(hit.score),
            "match_source": hit.match_source,
            "chunk_title": hit.chunk_title,
            "source_text": (hit.source_text or "")[:500],
        }
        for hit in results.contents
    ]
    events = []
    for hit in results.events:
        members = [
            member for member in hit.event.members if member.content is not None
        ]
        member_titles = [
            member.content.title for member in members if member.content.title
        ]
        events.append(
            {
                "kind": "event",
                "event_id": hit.event.id,
                "title": hit.event.title,
                "route": f"/events/{hit.event.id}",
                "match_source": hit.match_source,
                "source_text": (
                    hit.event.description or "；".join(member_titles)
                )[:500],
                "member_count": len(members),
            }
        )
    timepoints = [
        {
            "kind": "timepoint",
            "content_id": hit.content_id,
            "content_title": hit.content_title,
            "media_asset_id": hit.media_asset_id,
            "media_type": hit.media_type,
            "segment_type": hit.segment_type,
            "title": hit.title,
            "route": (
                f"/collection/{hit.content_id}?t={hit.start_seconds:g}"
                f"&media_asset={hit.media_asset_id}"
            ),
            "score": float(hit.score),
            "match_source": hit.match_source,
            "source_text": hit.excerpt[:500],
            "start_seconds": hit.start_seconds,
            "end_seconds": hit.end_seconds,
        }
        for hit in results.timepoints
    ]

    return {
        "query": query,
        "top_k": top_k,
        "count": len(items) + len(events) + len(timepoints),
        "items": items,
        "events": events,
        "timepoints": timepoints,
    }
