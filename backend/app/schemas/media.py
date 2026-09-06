"""统一媒体 API contract。"""

from datetime import datetime
from enum import Enum
from typing import Any, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field

from app.models.media import (
    MediaArchiveStatus,
    MediaRole,
    MediaType,
    MediaVariantKind,
    MediaVariantStatus,
)
from app.schemas.base import UtcDatetime


class MediaPurpose(str, Enum):
    CARD = "card"
    DETAIL = "detail"
    PLAYBACK = "playback"


class MediaSourceKind(str, Enum):
    LOCAL_SIGNED = "local_signed"
    REMOTE_PROXY = "remote_proxy"
    REMOTE_DIRECT = "remote_direct"


class MediaSource(BaseModel):
    url: str
    source_kind: MediaSourceKind
    variant_id: Optional[int] = None
    variant_kind: Optional[MediaVariantKind] = None
    mime_type: Optional[str] = None
    codec: Optional[str] = None
    container: Optional[str] = None
    width: Optional[int] = None
    height: Optional[int] = None
    bitrate: Optional[int] = None
    size_bytes: Optional[int] = None
    client_fetch_allowed: bool = True
    expires_at: Optional[datetime] = None


class MediaAssetManifest(BaseModel):
    id: int
    content_id: int
    position: int = 0
    media_type: MediaType
    role: MediaRole
    alt_text: Optional[str] = None
    caption: Optional[str] = None
    width: Optional[int] = None
    height: Optional[int] = None
    duration_ms: Optional[int] = None
    archive_status: MediaArchiveStatus
    last_error: Optional[str] = None
    repairable: bool = False
    metadata: dict[str, Any] = Field(default_factory=dict)
    purpose: MediaPurpose
    sources: list[MediaSource] = Field(default_factory=list)
    generated_at: UtcDatetime

    model_config = ConfigDict(from_attributes=True)


class MediaSegmentItem(BaseModel):
    """A seekable chapter or transcript segment tied to one persisted asset."""

    media_asset_id: int
    media_type: MediaType
    segment_type: Literal["chapter", "transcript"]
    title: str
    excerpt: str = ""
    start_seconds: float = Field(..., ge=0)
    end_seconds: Optional[float] = Field(None, gt=0)


class MediaBookmarkCreate(BaseModel):
    media_asset_id: int = Field(..., ge=1)
    position_seconds: float = Field(..., ge=0, allow_inf_nan=False)
    note: Optional[str] = Field(None, max_length=2000)


class MediaBookmarkUpdate(BaseModel):
    note: Optional[str] = Field(None, max_length=2000)


class MediaBookmarkItem(BaseModel):
    id: int
    content_id: int
    media_asset_id: int
    position_seconds: float
    note: Optional[str] = None
    created_at: UtcDatetime
    updated_at: UtcDatetime


class MediaBookmarkListResponse(BaseModel):
    items: list[MediaBookmarkItem] = Field(default_factory=list)


class MediaBookmarkDeleteResponse(BaseModel):
    deleted: Literal[True]
    bookmark_id: int
    content_id: int


class MediaLocalFailureCode(str, Enum):
    BLOB_MISSING = "media_blob_missing"
    DECODE_FAILED = "media_decode_failed"


class MediaLocalFailureReport(BaseModel):
    """A client observation that the server verifies before changing media state."""

    variant_id: int = Field(..., ge=1)
    error_code: MediaLocalFailureCode


class MediaLocalFailureResult(BaseModel):
    asset_id: int
    variant_id: int
    outcome: str
    variant_status: MediaVariantStatus
    archive_status: MediaArchiveStatus
    repairable: bool
