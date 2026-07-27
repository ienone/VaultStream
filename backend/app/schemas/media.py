"""统一媒体 API contract。"""

from datetime import datetime
from enum import Enum
from typing import Any, Optional

from pydantic import BaseModel, ConfigDict, Field

from app.models.media import (
    MediaArchiveStatus,
    MediaRole,
    MediaType,
    MediaVariantKind,
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
