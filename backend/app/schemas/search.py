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
    content_type: Optional[str] = None
    effective_layout_type: Optional[str] = None
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


class UnifiedSearchEventItem(BaseModel):
    id: int
    title: str
    description: Optional[str] = None
    status: str
    member_count: int
    latest_member_title: Optional[str] = None
    match_source: str  # title | description | member
    created_at: OptionalUtcDatetime = None
    updated_at: OptionalUtcDatetime = None


class UnifiedSearchFacetItem(BaseModel):
    name: str
    content_count: int
    latest_content_id: int
    latest_content_title: Optional[str] = None


class UnifiedSearchTimepointItem(BaseModel):
    content_id: int
    content_title: Optional[str] = None
    media_asset_id: int
    media_type: str
    segment_type: str
    title: str
    excerpt: str
    start_seconds: float
    end_seconds: Optional[float] = None
    match_source: str
    score: float


class UnifiedSearchResponse(BaseModel):
    query: str
    kind: str
    content_scope: str
    contents: List[SemanticSearchItem]
    events: List[UnifiedSearchEventItem]
    people: List[UnifiedSearchFacetItem]
    topics: List[UnifiedSearchFacetItem]
    timepoints: List[UnifiedSearchTimepointItem]


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


class SemanticEmbeddingRetryResponse(BaseModel):
    """单个语义分块已同步重试，且运行结果已写入任务账本。"""

    run_id: str
    embedding_id: int
    content_id: int
    chunk_index: int
    chunk_title: Optional[str] = None
    index_status: str
    failure_reason: Optional[str] = None
    retry_count: int
    last_attempted_at: OptionalUtcDatetime = None
    last_indexed_at: OptionalUtcDatetime = None


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
