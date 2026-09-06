"""
Discovery 相关 schemas
"""
from datetime import datetime
from typing import Optional, List, Literal
from pydantic import BaseModel, ConfigDict, Field

from app.models import ContentStatus, DiscoverySourceKind, DiscoveryState
from app.schemas.base import UtcDatetime, OptionalUtcDatetime
from app.schemas.media import MediaAssetManifest


# --- Discovery Item ---

class DiscoveryItemListItem(BaseModel):
    """列表精简版 — 只包含卡片渲染所需字段"""
    id: int
    title: Optional[str] = None
    url: str
    status: Optional[ContentStatus] = None
    author_name: Optional[str] = None
    summary: Optional[str] = None
    preview_text: Optional[str] = None
    ai_score: Optional[float] = None
    ai_tags: Optional[list] = None
    source_type: Optional[str] = None
    discovery_state: Optional[DiscoveryState] = None
    discovered_at: OptionalUtcDatetime = None
    published_at: OptionalUtcDatetime = None
    created_at: UtcDatetime
    cover_url: Optional[str] = None
    cover_color: Optional[str] = None
    media_assets: List[MediaAssetManifest] = Field(
        default_factory=list,
        validation_alias="media_asset_manifests",
    )
    discovery_source_id: Optional[int] = None
    source_names: List[str] = Field(default_factory=list)
    source_kinds: List[str] = Field(default_factory=list)
    source_count: int = 0

    model_config = ConfigDict(from_attributes=True)


class DiscoveryItemResponse(BaseModel):
    """详情完整版 — 包含正文、媒体、富负载等"""
    id: int
    title: Optional[str] = None
    url: str
    body: Optional[str] = None
    status: Optional[ContentStatus] = None
    author_name: Optional[str] = None
    author_avatar_url: Optional[str] = None
    author_url: Optional[str] = None
    summary: Optional[str] = None
    ai_score: Optional[float] = None
    ai_reason: Optional[str] = None
    ai_tags: Optional[list] = None
    source_type: Optional[str] = None
    discovery_state: Optional[DiscoveryState] = None
    discovered_at: OptionalUtcDatetime = None
    published_at: OptionalUtcDatetime = None
    created_at: UtcDatetime
    cover_url: Optional[str] = None
    cover_color: Optional[str] = None
    platform_id: Optional[str] = None
    content_type: Optional[str] = None
    layout_type: Optional[str] = Field(None, alias="layout_type")
    source_tags: List[str] = Field(default_factory=list)
    collect_count: int = 0
    share_count: int = 0
    comment_count: int = 0
    media_urls: List[str] = Field(default_factory=list)
    media_assets: List[MediaAssetManifest] = Field(
        default_factory=list,
        validation_alias="media_asset_manifests",
    )
    rich_payload: Optional[dict] = None
    extra_stats: dict = Field(default_factory=dict)
    context_data: Optional[dict] = None
    discovery_source_id: Optional[int] = None
    source_names: List[str] = Field(default_factory=list)
    source_kinds: List[str] = Field(default_factory=list)
    source_count: int = 0

    model_config = ConfigDict(from_attributes=True)


class DiscoveryItemListResponse(BaseModel):
    items: List[DiscoveryItemListItem] = Field(default_factory=list)
    total: int = 0
    page: int = 1
    size: int = 20
    has_more: bool = False


class DiscoveryItemUpdate(BaseModel):
    state: Literal["promoted", "ignored", "snoozed", "visible"]


class DiscoveryBulkAction(BaseModel):
    ids: List[int]
    action: Literal["promote", "ignore", "snooze"]


class DiscoveryBulkActionResponse(BaseModel):
    updated: int

    model_config = ConfigDict(extra="forbid")


# --- Discovery Source ---

class DiscoverySourceCreate(BaseModel):
    kind: DiscoverySourceKind
    name: str
    enabled: bool = True
    config: dict = Field(default_factory=dict)
    sync_interval_minutes: int = 60


class DiscoverySourceUpdate(BaseModel):
    name: Optional[str] = None
    enabled: Optional[bool] = None
    config: Optional[dict] = None
    sync_interval_minutes: Optional[int] = None


class DiscoverySourceResponse(BaseModel):
    id: int
    kind: DiscoverySourceKind
    name: str
    enabled: bool
    config: dict = Field(default_factory=dict)
    last_sync_at: OptionalUtcDatetime = None
    last_error: Optional[str] = None
    sync_interval_minutes: int
    created_at: UtcDatetime

    model_config = ConfigDict(from_attributes=True)


class DiscoverySourceDeleteResponse(BaseModel):
    success: Literal[True]
    id: int

    model_config = ConfigDict(extra="forbid")


class DiscoverySourceTestSample(BaseModel):
    url: str
    title: Optional[str] = None
    author: Optional[str] = None
    published_at: Optional[str] = None
    tag_count: int
    media_count: int


class DiscoverySourceTestResponse(BaseModel):
    run_id: str
    ok: bool
    status: Literal["ok", "empty", "error"]
    source_id: int
    source_name: str
    source_kind: str
    item_count: Optional[int] = None
    sample_count: Optional[int] = None
    samples: List[DiscoverySourceTestSample] = Field(default_factory=list)
    cursor_available: Optional[bool] = None
    elapsed_ms: float
    error: Optional[str] = None

    model_config = ConfigDict(extra="forbid")


class DiscoverySyncAcceptedResponse(BaseModel):
    status: Literal["accepted"]
    source_id: int
    run_id: str

    model_config = ConfigDict(extra="forbid")


# --- Discovery Settings ---

class DiscoverySettingsResponse(BaseModel):
    interest_profile: str = ""
    score_threshold: float = 6.0
    retention_days: int = 7
    cleanup_mode: Literal["hard_delete", "expire_only", "archive"] = "hard_delete"
    retention_scope: str = "new_candidates_only"


class DiscoverySettingsUpdate(BaseModel):
    interest_profile: Optional[str] = None
    score_threshold: Optional[float] = None
    retention_days: Optional[int] = None
    cleanup_mode: Optional[Literal["hard_delete", "expire_only", "archive"]] = None


# --- Stats ---

class DiscoveryStatsResponse(BaseModel):
    total: int = 0
    by_state: dict[str, int] = Field(default_factory=dict)
    by_source: dict[str, int] = Field(default_factory=dict)
