from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional

from app.services.agent.tool_registry import AgentToolContext, AgentToolRegistry
from app.services.embedding_service import EmbeddingService


def register_search_tool(registry: AgentToolRegistry) -> None:
    registry.register(
        name="search_content",
        description="语义检索内容库，支持平台和时间过滤。",
        args_schema={
            "query": {"type": "string", "required": True},
            "top_k": {"type": "integer", "required": False, "default": 10},
            "platform": {"type": "string", "required": False},
            "date_from": {"type": "string", "required": False, "format": "iso8601"},
            "date_to": {"type": "string", "required": False, "format": "iso8601"},
        },
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

    hits = await EmbeddingService().search(
        query=query,
        top_k=top_k,
        platform=platform,
        date_from=date_from,
        date_to=date_to,
        session=context.db,
    )

    return {
        "query": query,
        "top_k": top_k,
        "count": len(hits),
        "items": [
            {
                "content_id": hit.content.id,
                "platform": hit.content.platform.value if hit.content.platform else "",
                "title": hit.content.title,
                "url": hit.content.url,
                "score": float(hit.score),
                "match_source": hit.match_source,
            }
            for hit in hits
        ],
    }
