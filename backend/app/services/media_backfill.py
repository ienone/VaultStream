"""从解析结果构建统一媒体资产，并支持旧数据幂等回填。"""

from __future__ import annotations

import ipaddress
import mimetypes
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import urlparse

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.adapters.storage import LocalStorageBackend
from app.models import Content
from app.models.media import (
    MediaArchiveStatus,
    MediaAsset,
    MediaRole,
    MediaType,
    MediaVariant,
    MediaVariantKind,
    MediaVariantStatus,
)


@dataclass(frozen=True)
class MediaVariantCandidate:
    kind: MediaVariantKind
    storage_key: str
    mime_type: str | None = None
    width: int | None = None
    height: int | None = None
    size_bytes: int | None = None
    checksum: str | None = None


@dataclass
class MediaAssetCandidate:
    media_type: MediaType
    role: MediaRole
    position: int
    original_url: str | None = None
    width: int | None = None
    height: int | None = None
    duration_ms: int | None = None
    alt_text: str | None = None
    caption: str | None = None
    variants: list[MediaVariantCandidate] = field(default_factory=list)


@dataclass
class MediaBackfillReport:
    contents_scanned: int = 0
    contents_with_candidates: int = 0
    contents_skipped_existing: int = 0
    assets: int = 0
    image_assets: int = 0
    video_assets: int = 0
    audio_assets: int = 0
    local_variants: int = 0
    missing_local_variants: int = 0
    remote_originals: int = 0
    local_without_original: int = 0
    applied_contents: int = 0

    def to_dict(self) -> dict[str, int]:
        return dict(self.__dict__)


def _archive_blob(metadata: Any) -> dict[str, Any]:
    if not isinstance(metadata, dict):
        return {}
    archive = metadata.get("archive")
    if isinstance(archive, dict):
        return archive
    processed_archive = metadata.get("processed_archive")
    return processed_archive if isinstance(processed_archive, dict) else {}


def _text(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    value = value.strip()
    return value or None


def _local_key(value: Any) -> str | None:
    value = _text(value)
    if value and value.startswith("local://"):
        return value.removeprefix("local://")
    return None


def _remote_url(value: Any) -> str | None:
    value = _text(value)
    if value and urlparse(value).scheme.lower() in {"http", "https"}:
        return value
    return None


def is_client_direct_allowed(url: str | None) -> bool:
    """迁移策略：只允许无凭证、非本地域名或私网字面量的 HTTP(S) URL。"""
    if not url:
        return False
    parsed = urlparse(url)
    if parsed.scheme.lower() not in {"http", "https"} or not parsed.hostname:
        return False
    if parsed.username or parsed.password:
        return False
    hostname = parsed.hostname.lower().rstrip(".")
    if hostname == "localhost" or hostname.endswith((".localhost", ".local")):
        return False
    try:
        address = ipaddress.ip_address(hostname)
    except ValueError:
        return True
    return not (
        address.is_private
        or address.is_loopback
        or address.is_link_local
        or address.is_multicast
        or address.is_reserved
        or address.is_unspecified
    )


def _role_from_item(
    item: dict[str, Any],
    *,
    original_url: str | None,
    storage_key: str | None,
    cover_url: str | None,
    avatar_url: str | None,
    default_role: MediaRole,
) -> MediaRole:
    item_type = str(item.get("type") or "").lower()
    if item_type == "avatar" or item.get("is_avatar") is True:
        return MediaRole.AVATAR
    if item_type == "cover":
        return MediaRole.COVER
    if original_url and original_url == _remote_url(avatar_url):
        return MediaRole.AVATAR
    if storage_key and storage_key == _local_key(avatar_url):
        return MediaRole.AVATAR
    if original_url and original_url == _remote_url(cover_url):
        return MediaRole.COVER
    if storage_key and storage_key == _local_key(cover_url):
        return MediaRole.COVER
    return default_role


def _variant_from_item(
    item: dict[str, Any],
    *,
    kind: MediaVariantKind,
    key_names: tuple[str, ...],
    default_mime: str | None,
) -> MediaVariantCandidate | None:
    key = next((_text(item.get(name)) for name in key_names if _text(item.get(name))), None)
    if not key:
        return None
    return MediaVariantCandidate(
        kind=kind,
        storage_key=key,
        mime_type=_text(item.get("content_type"))
        or _text(item.get("stored_content_type"))
        or default_mime,
        width=item.get("width") or item.get("stored_width"),
        height=item.get("height") or item.get("stored_height"),
        size_bytes=item.get("size") or item.get("stored_size"),
        checksum=_text(item.get("sha256")) or _text(item.get("stored_sha256")),
    )


def _merge_stored_items(
    source_items: Iterable[Any],
    stored_items: Iterable[Any],
) -> list[dict[str, Any]]:
    merged = [dict(item) for item in source_items if isinstance(item, dict)]
    by_original = {
        _text(item.get("url")): item for item in merged if _text(item.get("url"))
    }
    by_key = {
        _text(item.get("stored_key")): item
        for item in merged
        if _text(item.get("stored_key"))
    }
    for stored in stored_items:
        if not isinstance(stored, dict):
            continue
        original = _text(stored.get("orig_url"))
        key = _text(stored.get("key")) or _text(stored.get("stored_key"))
        target = by_original.get(original) or by_key.get(key)
        if target is None:
            target = {}
            merged.append(target)
        if original and not _text(target.get("url")):
            target["url"] = original
        if key and not _text(target.get("stored_key")):
            target["stored_key"] = key
        for name in ("type", "is_avatar", "sha256", "size", "width", "height", "content_type"):
            if stored.get(name) is not None and target.get(name) is None:
                target[name] = stored[name]
    return merged


def build_media_candidates(content: Content) -> list[MediaAssetCandidate]:
    archive = _archive_blob(content.archive_metadata)
    image_items = _merge_stored_items(
        archive.get("images") or [],
        archive.get("stored_images") or [],
    )
    video_items = _merge_stored_items(
        archive.get("videos") or [],
        archive.get("stored_videos") or [],
    )
    is_gallery = getattr(content.layout_type, "value", content.layout_type) == "gallery"
    image_default_role = MediaRole.GALLERY if is_gallery else MediaRole.BODY

    candidates: list[MediaAssetCandidate] = []
    role_positions: dict[tuple[MediaType, MediaRole], int] = {}
    identities: set[tuple[MediaType, MediaRole, str]] = set()

    def add_candidate(candidate: MediaAssetCandidate) -> None:
        identity_value = candidate.original_url or (
            candidate.variants[0].storage_key if candidate.variants else ""
        )
        identity = (candidate.media_type, candidate.role, identity_value)
        if not identity_value or identity in identities:
            return
        identities.add(identity)
        key = (candidate.media_type, candidate.role)
        candidate.position = role_positions.get(key, 0)
        role_positions[key] = candidate.position + 1
        candidates.append(candidate)

    for item in image_items:
        original = _remote_url(item.get("url")) or _remote_url(item.get("orig_url"))
        stored = _text(item.get("stored_key")) or _text(item.get("key"))
        role = _role_from_item(
            item,
            original_url=original,
            storage_key=stored,
            cover_url=content.cover_url,
            avatar_url=content.author_avatar_url,
            default_role=image_default_role,
        )
        variants = []
        thumb = _variant_from_item(
            item,
            kind=MediaVariantKind.THUMBNAIL,
            key_names=("thumb_key",),
            default_mime="image/webp",
        )
        optimized = _variant_from_item(
            item,
            kind=MediaVariantKind.OPTIMIZED,
            key_names=("stored_key", "key"),
            default_mime="image/webp",
        )
        if thumb and (not optimized or thumb.storage_key != optimized.storage_key):
            variants.append(thumb)
        if optimized:
            variants.append(optimized)
        add_candidate(
            MediaAssetCandidate(
                media_type=MediaType.IMAGE,
                role=role,
                position=0,
                original_url=original,
                width=item.get("width") or item.get("stored_width"),
                height=item.get("height") or item.get("stored_height"),
                alt_text=_text(item.get("alt")) or _text(item.get("alt_text")),
                caption=_text(item.get("caption")),
                variants=variants,
            )
        )

    for role, raw_url in (
        (MediaRole.COVER, content.cover_url),
        (MediaRole.AVATAR, content.author_avatar_url),
    ):
        local_key = _local_key(raw_url)
        original = _remote_url(raw_url)
        variants = []
        if local_key:
            variants.append(
                MediaVariantCandidate(
                    kind=MediaVariantKind.OPTIMIZED,
                    storage_key=local_key,
                    mime_type=mimetypes.guess_type(local_key)[0] or "image/webp",
                )
            )
        add_candidate(
            MediaAssetCandidate(
                media_type=MediaType.IMAGE,
                role=role,
                position=0,
                original_url=original,
                variants=variants,
            )
        )

    for item in video_items:
        original = _remote_url(item.get("url")) or _remote_url(item.get("orig_url"))
        variant = _variant_from_item(
            item,
            kind=MediaVariantKind.ORIGINAL_ARCHIVE,
            key_names=("stored_key", "key"),
            default_mime="video/mp4",
        )
        add_candidate(
            MediaAssetCandidate(
                media_type=MediaType.VIDEO,
                role=MediaRole.ATTACHMENT,
                position=0,
                original_url=original,
                duration_ms=item.get("duration_ms"),
                variants=[variant] if variant else [],
            )
        )

    known_values = {
        candidate.original_url for candidate in candidates if candidate.original_url
    }
    known_values.update(
        variant.storage_key
        for candidate in candidates
        for variant in candidate.variants
    )
    for raw_url in content.media_urls or []:
        original = _remote_url(raw_url)
        local_key = _local_key(raw_url)
        identity = original or local_key
        if not identity or identity in known_values:
            continue
        mime = mimetypes.guess_type(identity)[0]
        media_type = (
            MediaType.VIDEO
            if mime and mime.startswith("video/")
            else MediaType.AUDIO
            if mime and mime.startswith("audio/")
            else MediaType.IMAGE
        )
        role = image_default_role if media_type == MediaType.IMAGE else MediaRole.ATTACHMENT
        variant = None
        if local_key:
            variant = MediaVariantCandidate(
                kind=(
                    MediaVariantKind.OPTIMIZED
                    if media_type == MediaType.IMAGE
                    else MediaVariantKind.ORIGINAL_ARCHIVE
                ),
                storage_key=local_key,
                mime_type=mime,
            )
        add_candidate(
            MediaAssetCandidate(
                media_type=media_type,
                role=role,
                position=0,
                original_url=original,
                variants=[variant] if variant else [],
            )
        )
        known_values.add(identity)

    if not any(item.role == MediaRole.COVER for item in candidates):
        first_image = next(
            (item for item in candidates if item.media_type == MediaType.IMAGE and item.role != MediaRole.AVATAR),
            None,
        )
        if first_image is not None:
            first_image.role = MediaRole.COVER
            first_image.position = 0

    return candidates


def _variant_path(storage: LocalStorageBackend, key: str) -> Path:
    return Path(storage._full_path(key)).resolve()


async def replace_content_media_assets(
    session: AsyncSession,
    content: Content,
    storage: LocalStorageBackend,
    *,
    source: str,
) -> list[MediaAsset]:
    candidates = build_media_candidates(content)
    await session.execute(delete(MediaAsset).where(MediaAsset.content_id == content.id))
    assets: list[MediaAsset] = []
    for candidate in candidates:
        ready_count = sum(
            1 for variant in candidate.variants if _variant_path(storage, variant.storage_key).is_file()
        )
        missing_count = len(candidate.variants) - ready_count
        archive_status = (
            MediaArchiveStatus.READY
            if ready_count and not missing_count
            else MediaArchiveStatus.PARTIAL
            if ready_count
            else MediaArchiveStatus.MISSING
        )
        asset = MediaAsset(
            content_id=content.id,
            position=candidate.position,
            media_type=candidate.media_type,
            role=candidate.role,
            original_url=candidate.original_url,
            client_fetch_allowed=is_client_direct_allowed(candidate.original_url),
            alt_text=candidate.alt_text,
            caption=candidate.caption,
            width=candidate.width,
            height=candidate.height,
            duration_ms=candidate.duration_ms,
            archive_status=archive_status,
            last_error="legacy_local_blob_missing" if missing_count else None,
            repairable=bool(candidate.original_url),
            asset_metadata={"write_source": source},
        )
        for variant in candidate.variants:
            exists = _variant_path(storage, variant.storage_key).is_file()
            asset.variants.append(
                MediaVariant(
                    variant_kind=variant.kind,
                    storage_key=variant.storage_key,
                    mime_type=variant.mime_type,
                    width=variant.width,
                    height=variant.height,
                    size_bytes=variant.size_bytes,
                    checksum=variant.checksum,
                    status=MediaVariantStatus.READY if exists else MediaVariantStatus.MISSING,
                )
            )
        session.add(asset)
        assets.append(asset)
    await session.flush()
    return assets


async def backfill_media_assets(
    session: AsyncSession,
    storage: LocalStorageBackend,
    *,
    apply: bool = False,
) -> MediaBackfillReport:
    contents = (await session.execute(select(Content).order_by(Content.id))).scalars().all()
    existing_content_ids = set(
        (await session.execute(select(MediaAsset.content_id).distinct())).scalars().all()
    )
    report = MediaBackfillReport(contents_scanned=len(contents))
    for content in contents:
        if content.id in existing_content_ids:
            report.contents_skipped_existing += 1
            continue
        candidates = build_media_candidates(content)
        if not candidates:
            continue
        report.contents_with_candidates += 1
        report.assets += len(candidates)
        for candidate in candidates:
            if candidate.media_type == MediaType.IMAGE:
                report.image_assets += 1
            elif candidate.media_type == MediaType.VIDEO:
                report.video_assets += 1
            elif candidate.media_type == MediaType.AUDIO:
                report.audio_assets += 1
            if candidate.original_url:
                report.remote_originals += 1
            elif candidate.variants:
                report.local_without_original += 1
            for variant in candidate.variants:
                report.local_variants += 1
                if not _variant_path(storage, variant.storage_key).is_file():
                    report.missing_local_variants += 1
        if apply:
            await replace_content_media_assets(
                session,
                content,
                storage,
                source="legacy_backfill_v1",
            )
            report.applied_contents += 1
    if apply:
        await session.commit()
    return report
