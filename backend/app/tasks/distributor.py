"""内容分发 payload 构建。"""

from collections.abc import Iterable

from app.models import (
    Content,
    DistributionRule,
    MediaAsset,
    MediaRole,
    MediaType,
    MediaVariantKind,
    MediaVariantStatus,
)
from app.schemas import ContentPushPayload


_PLATFORM_MEDIA_TYPES = {
    "telegram": {
        MediaType.IMAGE: "photo",
        MediaType.VIDEO: "video",
    },
    "qq": {
        MediaType.IMAGE: "photo",
        MediaType.VIDEO: "video",
        MediaType.AUDIO: "audio",
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

_VARIANT_PRIORITY = {
    MediaType.IMAGE: {
        MediaVariantKind.OPTIMIZED: 0,
        MediaVariantKind.ORIGINAL_ARCHIVE: 1,
        MediaVariantKind.THUMBNAIL: 2,
        MediaVariantKind.POSTER: 3,
    },
    MediaType.VIDEO: {
        MediaVariantKind.TRANSCODE: 0,
        MediaVariantKind.ORIGINAL_ARCHIVE: 1,
        MediaVariantKind.STREAM: 2,
    },
    MediaType.AUDIO: {
        MediaVariantKind.TRANSCODE: 0,
        MediaVariantKind.ORIGINAL_ARCHIVE: 1,
        MediaVariantKind.STREAM: 2,
    },
}


def build_push_media_items(
    media_assets: Iterable[MediaAsset],
    *,
    target_platform: str,
) -> list[dict]:
    """Select one ordered upload source per asset for a target platform."""
    supported_types = _PLATFORM_MEDIA_TYPES.get(target_platform.lower(), {})
    if not supported_types:
        return []

    ordered_assets = sorted(
        media_assets,
        key=lambda asset: (
            _ROLE_PRIORITY.get(asset.role, 99),
            asset.position,
            asset.id or 0,
        ),
    )
    media_items: list[dict] = []
    seen: set[tuple[str, str]] = set()

    for asset in ordered_assets:
        item_type = supported_types.get(asset.media_type)
        if item_type is None or asset.role == MediaRole.AVATAR:
            continue

        priorities = _VARIANT_PRIORITY.get(asset.media_type, {})
        ready_variants = sorted(
            (
                variant
                for variant in asset.variants
                if variant.status == MediaVariantStatus.READY
                and variant.variant_kind in priorities
            ),
            key=lambda variant: (
                priorities[variant.variant_kind],
                variant.id or 0,
            ),
        )
        local_variant = ready_variants[0] if ready_variants else None
        remote_url = (
            asset.original_url.strip()
            if asset.client_fetch_allowed
            and isinstance(asset.original_url, str)
            and asset.original_url.strip()
            else None
        )
        if local_variant is None and remote_url is None:
            continue

        identity = local_variant.storage_key if local_variant else remote_url
        dedupe_key = (item_type, identity)
        if dedupe_key in seen:
            continue
        seen.add(dedupe_key)

        item = {
            "type": item_type,
            "asset_id": asset.id,
        }
        if local_variant is not None:
            item.update(
                stored_key=local_variant.storage_key,
                variant_kind=local_variant.variant_kind.value,
                mime_type=local_variant.mime_type,
            )
        if remote_url is not None:
            item["url"] = remote_url
        media_items.append(item)

    return media_items


class ContentDistributor:
    """内容分发器。"""

    async def _build_content_payload(
        self,
        content: Content,
        rule: DistributionRule | None,
        target_render_config: dict | None = None,
        *,
        media_assets: Iterable[MediaAsset] = (),
        target_platform: str,
    ) -> dict:
        # 通过 Pydantic schema 自动映射 ORM 字段
        payload = ContentPushPayload.model_validate(content).model_dump()

        # platform 需要转为字符串值（ORM 存储的是 enum）
        if content.platform:
            payload["platform"] = content.platform.value

        # render_config 合并逻辑：rule 级 → target 级覆盖
        if rule and rule.render_config:
            payload["render_config"] = rule.render_config
        if target_render_config:
            base = payload.get("render_config") or {}
            payload["render_config"] = {**base, **target_render_config}

        payload["media_items"] = build_push_media_items(
            media_assets,
            target_platform=target_platform,
        )

        return payload
