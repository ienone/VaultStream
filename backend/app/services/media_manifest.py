"""按用途生成统一媒体候选。"""

import time
from datetime import datetime, timezone
from urllib.parse import quote

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import settings
from app.core.safe_fetch import is_safe_url
from app.models.media import (
    MediaAsset,
    MediaRole,
    MediaType,
    MediaVariantKind,
    MediaVariantStatus,
)
from app.schemas.media import MediaAssetManifest, MediaPurpose, MediaSource, MediaSourceKind
from app.services.media_access import build_signed_media_url


_VARIANT_PRIORITY = {
    MediaPurpose.CARD: {
        MediaVariantKind.THUMBNAIL: 0,
        MediaVariantKind.OPTIMIZED: 1,
        MediaVariantKind.POSTER: 2,
        MediaVariantKind.ORIGINAL_ARCHIVE: 3,
        MediaVariantKind.TRANSCODE: 4,
        MediaVariantKind.STREAM: 5,
    },
    MediaPurpose.DETAIL: {
        MediaVariantKind.OPTIMIZED: 0,
        MediaVariantKind.ORIGINAL_ARCHIVE: 1,
        MediaVariantKind.THUMBNAIL: 2,
        MediaVariantKind.POSTER: 3,
        MediaVariantKind.TRANSCODE: 4,
        MediaVariantKind.STREAM: 5,
    },
    MediaPurpose.PLAYBACK: {
        MediaVariantKind.TRANSCODE: 0,
        MediaVariantKind.STREAM: 1,
        MediaVariantKind.ORIGINAL_ARCHIVE: 2,
        MediaVariantKind.OPTIMIZED: 3,
        MediaVariantKind.POSTER: 4,
        MediaVariantKind.THUMBNAIL: 5,
    },
}

_ROLE_PRIORITY = {
    MediaRole.COVER: 0,
    MediaRole.POSTER: 1,
    MediaRole.BODY: 2,
    MediaRole.GALLERY: 3,
    MediaRole.ATTACHMENT: 4,
    MediaRole.AVATAR: 5,
}


def resolve_media_base_url(request_base_url: str) -> str:
    """媒体 URL 跟随客户端实际访问 origin；仅显式媒体 CDN 可覆盖。"""
    return (settings.storage_public_base_url or request_base_url).rstrip("/")


def _content_asset_priority(asset: MediaAsset, purpose: MediaPurpose) -> tuple[int, ...]:
    role_priority = _ROLE_PRIORITY.get(asset.role, 99)
    if purpose == MediaPurpose.CARD:
        has_ready_local = any(
            variant.status == MediaVariantStatus.READY for variant in asset.variants
        )
        return (
            0 if asset.media_type == MediaType.IMAGE else 1,
            0 if has_ready_local else 1,
            role_priority,
            asset.position,
            asset.id,
        )
    return (role_priority, asset.position, asset.id)


async def get_media_asset(session: AsyncSession, asset_id: int) -> MediaAsset | None:
    result = await session.execute(
        select(MediaAsset)
        .where(MediaAsset.id == asset_id)
        .options(selectinload(MediaAsset.variants))
    )
    return result.scalar_one_or_none()


async def build_content_media_manifests(
    session: AsyncSession,
    content_ids: list[int],
    *,
    purpose: MediaPurpose,
    base_url: str,
) -> dict[int, list[MediaAssetManifest]]:
    """批量生成内容媒体，避免列表接口逐条查询。"""
    if not content_ids:
        return {}
    result = await session.execute(
        select(MediaAsset)
        .where(MediaAsset.content_id.in_(content_ids))
        .options(selectinload(MediaAsset.variants))
        .order_by(MediaAsset.content_id, MediaAsset.position, MediaAsset.id)
    )
    assets_by_content: dict[int, list[MediaAsset]] = {
        content_id: [] for content_id in content_ids
    }
    for asset in result.scalars().unique():
        assets_by_content.setdefault(asset.content_id, []).append(asset)
    grouped: dict[int, list[MediaAssetManifest]] = {}
    for content_id, assets in assets_by_content.items():
        assets.sort(key=lambda asset: _content_asset_priority(asset, purpose))
        grouped[content_id] = [
            build_media_manifest(asset, purpose=purpose, base_url=base_url)
            for asset in assets
        ]
    return grouped


def build_media_manifest(
    asset: MediaAsset,
    *,
    purpose: MediaPurpose,
    base_url: str,
    now: int | None = None,
) -> MediaAssetManifest:
    issued_at = int(time.time()) if now is None else now
    expires = issued_at + settings.media_url_ttl_seconds
    priorities = _VARIANT_PRIORITY[purpose]
    ready_variants = sorted(
        (item for item in asset.variants if item.status == MediaVariantStatus.READY),
        key=lambda item: (priorities.get(item.variant_kind, 99), item.id),
    )

    sources: list[MediaSource] = []
    seen_urls: set[str] = set()
    for variant in ready_variants:
        url = build_signed_media_url(
            base_url,
            variant.storage_key,
            variant.id,
            expires=expires,
        )
        if url in seen_urls:
            continue
        seen_urls.add(url)
        sources.append(
            MediaSource(
                url=url,
                source_kind=MediaSourceKind.LOCAL_SIGNED,
                variant_kind=variant.variant_kind,
                mime_type=variant.mime_type,
                codec=variant.codec,
                container=variant.container,
                width=variant.width,
                height=variant.height,
                bitrate=variant.bitrate,
                size_bytes=variant.size_bytes,
                expires_at=datetime.fromtimestamp(expires, timezone.utc),
            )
        )

    original_url = asset.original_url
    if original_url and asset.media_type == MediaType.IMAGE and is_safe_url(original_url):
        proxy_url = f"{base_url.rstrip('/')}/api/v1/proxy/image?url={quote(original_url, safe='')}"
        if proxy_url not in seen_urls:
            seen_urls.add(proxy_url)
            sources.append(
                MediaSource(
                    url=proxy_url,
                    source_kind=MediaSourceKind.REMOTE_PROXY,
                    mime_type=None,
                )
            )

    if original_url and asset.client_fetch_allowed and original_url not in seen_urls:
        sources.append(
            MediaSource(
                url=original_url,
                source_kind=MediaSourceKind.REMOTE_DIRECT,
                client_fetch_allowed=True,
            )
        )

    return MediaAssetManifest(
        id=asset.id,
        content_id=asset.content_id,
        position=asset.position,
        media_type=asset.media_type,
        role=asset.role,
        alt_text=asset.alt_text,
        caption=asset.caption,
        width=asset.width,
        height=asset.height,
        duration_ms=asset.duration_ms,
        archive_status=asset.archive_status,
        last_error=asset.last_error,
        repairable=asset.repairable,
        metadata=asset.asset_metadata or {},
        purpose=purpose,
        sources=sources,
        generated_at=datetime.fromtimestamp(issued_at, timezone.utc),
    )
