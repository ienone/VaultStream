"""
语义检索相关 schema
"""
from typing import List, Optional

from pydantic import BaseModel, ConfigDict

from app.schemas.base import OptionalUtcDatetime


class SemanticSearchItem(BaseModel):
    content_id: int
    score: float
    match_source: str  # vector | fts | hybrid

    platform: str
    url: str
    title: Optional[str] = None
    summary: Optional[str] = None
    author_name: Optional[str] = None
    cover_url: Optional[str] = None
    tags: List[str] = []
    created_at: OptionalUtcDatetime = None
    published_at: OptionalUtcDatetime = None

    model_config = ConfigDict(from_attributes=True)


class SemanticSearchResponse(BaseModel):
    query: str
    top_k: int
    results: List[SemanticSearchItem]
