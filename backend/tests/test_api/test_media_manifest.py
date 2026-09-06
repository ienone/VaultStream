import time
import uuid
from pathlib import Path
import pytest
from httpx import AsyncClient
from pydantic import SecretStr
from app.core.config import settings
from app.models import Content, Platform, MediaAsset, MediaType, MediaRole, MediaArchiveStatus, MediaVariant, MediaVariantKind, MediaVariantStatus
from app.services.media_access import sign_media_key


@pytest.fixture
async def stored_media_asset(db_session):
    suffix = uuid.uuid4().hex
    content = Content(platform=Platform.UNIVERSAL, url=f"https://example.test/{suffix}")
    db_session.add(content)
    await db_session.flush()

    asset = MediaAsset(
        content_id=content.id,
        media_type=MediaType.IMAGE,
        role=MediaRole.COVER,
        original_url="https://images.example.test/cover.jpg",
        client_fetch_allowed=True,
        archive_status=MediaArchiveStatus.READY,
    )
    db_session.add(asset)
    await db_session.flush()
    variant = MediaVariant(
        asset_id=asset.id,
        variant_kind=MediaVariantKind.OPTIMIZED,
        storage_key=f"tests/{suffix}/cover.webp",
        mime_type="image/webp",
        status=MediaVariantStatus.READY,
    )
    db_session.add(variant)
    await db_session.commit()

    file_path = Path(settings.storage_local_root) / variant.storage_key
    file_path.parent.mkdir(parents=True, exist_ok=True)
    file_path.write_bytes(b"webp-test")
    return asset, variant, file_path


@pytest.mark.asyncio
async def test_signed_blob_is_readable_without_api_token(
    client: AsyncClient,
    stored_media_asset,
    monkeypatch,
):
    _, variant, _ = stored_media_asset
    monkeypatch.setattr(settings, "api_token", SecretStr("control-token"))
    monkeypatch.setattr(settings, "media_signing_secret", SecretStr("media-secret"))
    expires = int(time.time()) + 60
    signature = sign_media_key(variant.storage_key, variant.id, expires)

    response = await client.get(
        f"/api/v1/media/blobs/{variant.storage_key}",
        params={
            "variant_id": variant.id,
            "expires": expires,
            "signature": signature,
        },
        headers={"X-API-Token": ""},
    )

    assert response.status_code == 200
    assert response.content == b"webp-test"
    assert response.headers["content-type"] == "image/webp"


@pytest.mark.asyncio
async def test_signed_blob_rejects_expired_signature(
    client: AsyncClient,
    stored_media_asset,
    monkeypatch,
):
    _, variant, _ = stored_media_asset
    monkeypatch.setattr(settings, "media_signing_secret", SecretStr("media-secret"))
    signature = sign_media_key(variant.storage_key, variant.id, 1)

    response = await client.get(
        f"/api/v1/media/blobs/{variant.storage_key}",
        params={"variant_id": variant.id, "expires": 1, "signature": signature},
    )

    assert response.status_code == 410
    assert response.json()["error_code"] == "media_signature_expired"


@pytest.mark.asyncio
async def test_signed_blob_supports_range_without_control_token(
    client: AsyncClient,
    stored_media_asset,
    monkeypatch,
):
    _, variant, _ = stored_media_asset
    monkeypatch.setattr(settings, "api_token", SecretStr("control-token"))
    monkeypatch.setattr(settings, "media_signing_secret", SecretStr("media-secret"))
    expires = int(time.time()) + 60
    signature = sign_media_key(variant.storage_key, variant.id, expires)

    response = await client.get(
        f"/api/v1/media/blobs/{variant.storage_key}",
        params={
            "variant_id": variant.id,
            "expires": expires,
            "signature": signature,
        },
        headers={"Range": "bytes=0-3", "X-API-Token": ""},
    )

    assert response.status_code == 206
    assert response.content == b"webp"
    assert response.headers["content-range"] == "bytes 0-3/9"
