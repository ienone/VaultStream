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
    chunk_title: Optional[str] = None
    source_text: Optional[str] = None

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


class SemanticReindexRequest(BaseModel):
    content_id: Optional[int] = None
    scope: str = "single"  # single | all | failed
    limit: int = 100
    dry_run: bool = False


class SemanticReindexResponse(BaseModel):
    scope: str
    content_id: Optional[int] = None
    dry_run: bool = False
    candidate_count: int
    estimated_embedding_calls: int
    scheduled: bool
    message: str


class SemanticIndexStatusItem(BaseModel):
    status: str
    count: int


class SemanticIndexStatusResponse(BaseModel):
    contents_total: int
    parse_success_total: int
    indexed_total: int
    status_counts: List[SemanticIndexStatusItem]
    model_distribution: List[dict]
