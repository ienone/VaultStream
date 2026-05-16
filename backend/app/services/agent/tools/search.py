from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional

from pydantic import BaseModel, Field

from app.services.agent.tool_registry import AgentToolContext, AgentToolRegistry
from app.services.embedding_service import EmbeddingService


class SearchContentArgs(BaseModel):
    query: str = Field(min_length=1)
    top_k: int = Field(default=10, ge=1, le=100)
    platform: Optional[str] = None
    date_from: Optional[str] = None
    date_to: Optional[str] = None


def register_search_tool(registry: AgentToolRegistry) -> None:
    registry.register(
        name="search_content",
        description="语义检索内容库，支持平台和时间过滤。",
        args_model=SearchContentArgs,
        result_schema={
            "type": "object",
            "required": ["query", "top_k", "count", "items"],
            "properties": {
                "query": {"type": "string"},
                "top_k": {"type": "integer"},
                "count": {"type": "integer"},
                "items": {"type": "array"},
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
                "chunk_title": hit.chunk_title,
                "source_text": (hit.source_text or "")[:500],
            }
            for hit in hits
        ],
    }
