"""Validate structured chapter/transcript navigation against persisted media."""

from collections.abc import Iterable
from dataclasses import dataclass
import math

from app.models.media import MediaAsset, MediaType
from app.schemas.media import MediaAssetManifest, MediaSegmentItem


@dataclass(frozen=True, slots=True)
class ValidatedMediaSegment:
    chunk_index: int
    media_asset_id: int
    media_type: MediaType
    segment_type: str
    title: str
    excerpt: str
    start_seconds: float
    end_seconds: float | None


def extract_media_segments(
    *,
    content_id: int,
    rich_payload: object,
    assets: Iterable[MediaAsset | MediaAssetManifest],
) -> list[ValidatedMediaSegment]:
    """Return only explicit, same-content, in-range audio/video segments."""
    assets_by_id = {
        asset.id: asset
        for asset in assets
        if asset.content_id == content_id
        and asset.media_type in {MediaType.AUDIO, MediaType.VIDEO}
    }
    chunks = rich_payload.get("chunks", []) if isinstance(rich_payload, dict) else []
    if not isinstance(chunks, list) or not assets_by_id:
        return []

    segments: list[ValidatedMediaSegment] = []
    for chunk_index, chunk in enumerate(chunks):
        if not isinstance(chunk, dict):
            continue
        segment_type = chunk.get("segment_type")
        if segment_type not in {"chapter", "transcript"}:
            continue
        media_asset_id = chunk.get("media_asset_id")
        if isinstance(media_asset_id, bool) or not isinstance(media_asset_id, int):
            continue
        asset = assets_by_id.get(media_asset_id)
        if asset is None:
            continue
        start_seconds = _non_negative_number(chunk.get("start_seconds"))
        if start_seconds is None:
            continue
        end_value = chunk.get("end_seconds")
        end_seconds = None
        if end_value is not None:
            end_seconds = _non_negative_number(end_value)
            if end_seconds is None or end_seconds <= start_seconds:
                continue
        if asset.duration_ms is not None:
            if start_seconds * 1000 >= asset.duration_ms:
                continue
            if end_seconds is not None and end_seconds * 1000 > asset.duration_ms:
                continue
        title = str(chunk.get("title") or "").strip()
        excerpt = str(chunk.get("content") or "").strip()
        if not title and not excerpt:
            continue
        if not title:
            label = "章节" if segment_type == "chapter" else "转写"
            title = f"{label} · {_format_seconds(start_seconds)}"
        segments.append(
            ValidatedMediaSegment(
                chunk_index=chunk_index,
                media_asset_id=asset.id,
                media_type=asset.media_type,
                segment_type=segment_type,
                title=title,
                excerpt=excerpt[:280],
                start_seconds=start_seconds,
                end_seconds=end_seconds,
            )
        )

    return sorted(
        segments,
        key=lambda item: (item.media_asset_id, item.start_seconds, item.chunk_index),
    )


def build_media_segment_items(
    *,
    content_id: int,
    rich_payload: object,
    assets: Iterable[MediaAsset | MediaAssetManifest],
) -> list[MediaSegmentItem]:
    return [
        MediaSegmentItem(
            media_asset_id=item.media_asset_id,
            media_type=item.media_type,
            segment_type=item.segment_type,
            title=item.title,
            excerpt=item.excerpt,
            start_seconds=item.start_seconds,
            end_seconds=item.end_seconds,
        )
        for item in extract_media_segments(
            content_id=content_id,
            rich_payload=rich_payload,
            assets=assets,
        )
    ]


def _non_negative_number(value: object) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    parsed = float(value)
    return parsed if math.isfinite(parsed) and parsed >= 0 else None


def _format_seconds(value: float) -> str:
    total = int(value)
    hours, remainder = divmod(total, 3600)
    minutes, seconds = divmod(remainder, 60)
    return (
        f"{hours}:{minutes:02d}:{seconds:02d}"
        if hours
        else f"{minutes:02d}:{seconds:02d}"
    )
