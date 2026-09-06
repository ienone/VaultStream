"""统一媒体资产与变体模型。"""

from datetime import datetime
from enum import Enum
from typing import Any, Optional

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, Integer, JSON, String, Text, UniqueConstraint
from sqlalchemy import Enum as SQLEnum
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.time_utils import utcnow
from app.models.base import Base


def _enum_values(enum_type):
    return [item.value for item in enum_type]


class MediaType(str, Enum):
    IMAGE = "image"
    VIDEO = "video"
    AUDIO = "audio"
    DOCUMENT = "document"
    OTHER = "other"


class MediaRole(str, Enum):
    COVER = "cover"
    AVATAR = "avatar"
    BODY = "body"
    GALLERY = "gallery"
    POSTER = "poster"
    ATTACHMENT = "attachment"


class MediaArchiveStatus(str, Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    READY = "ready"
    PARTIAL = "partial"
    FAILED = "failed"
    MISSING = "missing"


class MediaVariantKind(str, Enum):
    THUMBNAIL = "thumbnail"
    OPTIMIZED = "optimized"
    ORIGINAL_ARCHIVE = "original_archive"
    POSTER = "poster"
    STREAM = "stream"
    TRANSCODE = "transcode"


class MediaVariantStatus(str, Enum):
    READY = "ready"
    PROCESSING = "processing"
    FAILED = "failed"
    MISSING = "missing"


class MediaAsset(Base):
    """有业务身份的媒体对象；URL 只是它的一个来源。"""

    __tablename__ = "media_assets"
    __table_args__ = (
        Index(
            "uq_media_asset_content_role_position",
            "content_id",
            "media_type",
            "role",
            "position",
            unique=True,
        ),
        Index("ix_media_assets_content_role_position", "content_id", "role", "position"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    content_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("contents.id", ondelete="CASCADE"),
        index=True,
    )
    position: Mapped[int] = mapped_column(Integer, default=0)
    media_type: Mapped[MediaType] = mapped_column(
        SQLEnum(MediaType, native_enum=False, values_callable=_enum_values),
        index=True,
    )
    role: Mapped[MediaRole] = mapped_column(
        SQLEnum(MediaRole, native_enum=False, values_callable=_enum_values),
        index=True,
    )
    original_url: Mapped[Optional[str]] = mapped_column(Text, default=None)
    client_fetch_allowed: Mapped[bool] = mapped_column(Boolean, default=False)
    alt_text: Mapped[Optional[str]] = mapped_column(Text, default=None)
    caption: Mapped[Optional[str]] = mapped_column(Text, default=None)
    width: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    height: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    duration_ms: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    archive_status: Mapped[MediaArchiveStatus] = mapped_column(
        SQLEnum(MediaArchiveStatus, native_enum=False, values_callable=_enum_values),
        default=MediaArchiveStatus.PENDING,
        index=True,
    )
    last_error: Mapped[Optional[str]] = mapped_column(Text, default=None)
    repairable: Mapped[bool] = mapped_column(Boolean, default=False)
    asset_metadata: Mapped[Optional[Any]] = mapped_column("metadata", JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)

    content = relationship("Content", back_populates="media_assets")
    variants = relationship(
        "MediaVariant",
        back_populates="asset",
        cascade="all, delete-orphan",
        order_by="MediaVariant.id",
    )
    bookmarks = relationship(
        "MediaBookmark",
        back_populates="asset",
        cascade="all, delete-orphan",
        order_by="MediaBookmark.position_ms",
    )


class MediaVariant(Base):
    """媒体资产的一个本地或可播放版本。"""

    __tablename__ = "media_variants"
    __table_args__ = (
        UniqueConstraint("asset_id", "variant_kind", "storage_key", name="uq_media_variant_storage"),
        Index("ix_media_variants_asset_status", "asset_id", "status"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    asset_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("media_assets.id", ondelete="CASCADE"),
        index=True,
    )
    variant_kind: Mapped[MediaVariantKind] = mapped_column(
        SQLEnum(MediaVariantKind, native_enum=False, values_callable=_enum_values),
        index=True,
    )
    storage_key: Mapped[str] = mapped_column(Text)
    mime_type: Mapped[Optional[str]] = mapped_column(String(200), default=None)
    codec: Mapped[Optional[str]] = mapped_column(String(100), default=None)
    container: Mapped[Optional[str]] = mapped_column(String(100), default=None)
    width: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    height: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    bitrate: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    size_bytes: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    status: Mapped[MediaVariantStatus] = mapped_column(
        SQLEnum(MediaVariantStatus, native_enum=False, values_callable=_enum_values),
        default=MediaVariantStatus.PROCESSING,
        index=True,
    )
    checksum: Mapped[Optional[str]] = mapped_column(String(128), default=None)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    asset = relationship("MediaAsset", back_populates="variants")


class MediaBookmark(Base):
    """A user-created playback position, optionally carrying a note."""

    __tablename__ = "media_bookmarks"
    __table_args__ = (
        UniqueConstraint(
            "media_asset_id",
            "position_ms",
            name="uq_media_bookmark_asset_position",
        ),
        Index(
            "ix_media_bookmarks_content_asset_position",
            "content_id",
            "media_asset_id",
            "position_ms",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    content_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("contents.id", ondelete="CASCADE"),
        index=True,
    )
    media_asset_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("media_assets.id", ondelete="CASCADE"),
        index=True,
    )
    position_ms: Mapped[int] = mapped_column(Integer)
    note: Mapped[Optional[str]] = mapped_column(Text, default=None)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=utcnow,
        onupdate=utcnow,
    )

    asset = relationship("MediaAsset", back_populates="bookmarks")
