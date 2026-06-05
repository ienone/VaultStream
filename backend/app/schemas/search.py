"""
语义检索相关 schema
"""
from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.base import OptionalUtcDatetime


class SemanticSearchItem(BaseModel):
    content_id: int
    score: float
    match_source: str  # vector | fts | hybrid
    chunk_title: Optional[str] = None
    source_text: Optional[str] = None

    platform: str
    url: str
    status: str
    review_status: Optional[str] = None
    discovery_state: Optional[str] = None
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
    scope: str = "library"
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
    run_id: Optional[str] = None
    message: str


class SemanticIndexStatusItem(BaseModel):
    status: str
    count: int


class SemanticIndexFailureItem(BaseModel):
    content_id: int
    title: Optional[str] = None
    chunk_index: int
    chunk_title: Optional[str] = None
    failure_reason: Optional[str] = None
    retry_count: int = 0
    last_attempted_at: OptionalUtcDatetime = None
    updated_at: OptionalUtcDatetime = None


class SemanticIndexStatusResponse(BaseModel):
    contents_total: int
    parse_success_total: int
    indexed_total: int
    pending_total: int = 0
    failed_total: int = 0
    last_attempt_at: OptionalUtcDatetime = None
    current_model_signature: Optional[str] = None
    status_counts: List[SemanticIndexStatusItem]
    model_distribution: List[dict]
    recent_failures: List[SemanticIndexFailureItem] = Field(default_factory=list)
