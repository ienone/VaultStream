import time
import uuid
from pathlib import Path

import pytest
from httpx import AsyncClient
from pydantic import SecretStr

from app.core.config import settings
from app.models import Content, Platform
from app.models.media import (
    MediaArchiveStatus,
    MediaAsset,
    MediaRole,
    MediaType,
    MediaVariant,
    MediaVariantKind,
    MediaVariantStatus,
)
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
async def test_manifest_orders_local_before_allowed_remote(
    client: AsyncClient,
    stored_media_asset,
    monkeypatch,
):
    asset, variant, _ = stored_media_asset
    monkeypatch.setattr(settings, "media_signing_secret", SecretStr("media-secret"))
    monkeypatch.setattr("app.services.media_manifest.is_safe_url", lambda _url: True)

    response = await client.get(f"/api/v1/media/assets/{asset.id}/manifest?purpose=card")

    assert response.status_code == 200
    data = response.json()
    assert data["media_type"] == "image"
    assert data["role"] == "cover"
    assert data["purpose"] == "card"
    assert [source["source_kind"] for source in data["sources"]] == [
        "local_signed",
        "remote_proxy",
        "remote_direct",
    ]
    assert data["sources"][0]["variant_kind"] == "optimized"
    assert f"variant_id={variant.id}" in data["sources"][0]["url"]
    assert "control-token" not in data["sources"][0]["url"]


@pytest.mark.asyncio
async def test_content_detail_and_card_expose_same_media_contract(
    client: AsyncClient,
    stored_media_asset,
    monkeypatch,
):
    asset, _, _ = stored_media_asset
    monkeypatch.setattr(settings, "media_signing_secret", SecretStr("media-secret"))

    detail_response = await client.get(f"/api/v1/contents/{asset.content_id}")
    card_response = await client.get(f"/api/v1/cards/{asset.content_id}")

    assert detail_response.status_code == 200
    assert card_response.status_code == 200
    detail_asset = detail_response.json()["media_assets"][0]
    card_asset = card_response.json()["media_assets"][0]
    assert detail_asset["id"] == card_asset["id"] == asset.id
    assert detail_asset["purpose"] == "detail"
    assert card_asset["purpose"] == "card"
    assert detail_asset["sources"][0]["source_kind"] == "local_signed"
    assert card_asset["sources"][0]["source_kind"] == "local_signed"

    list_response = await client.get("/api/v1/cards?page=1&size=100")
    assert list_response.status_code == 200
    list_card = next(
        item
        for item in list_response.json()["items"]
        if item["id"] == asset.content_id
    )
    assert list_card["media_assets"][0]["id"] == asset.id


@pytest.mark.asyncio
async def test_media_urls_follow_request_origin_instead_of_control_api_base_url(
    client: AsyncClient,
    stored_media_asset,
    monkeypatch,
):
    asset, _, _ = stored_media_asset
    monkeypatch.setattr(settings, "base_url", "http://localhost:8000")
    monkeypatch.setattr(settings, "storage_public_base_url", None)
    monkeypatch.setattr(settings, "media_signing_secret", SecretStr("media-secret"))

    response = await client.get(f"/api/v1/cards/{asset.content_id}")

    assert response.status_code == 200
    media_url = response.json()["media_assets"][0]["sources"][0]["url"]
    assert media_url.startswith("http://test/api/v1/media/blobs/")
    assert "localhost:8000" not in media_url


@pytest.mark.asyncio
async def test_card_orders_local_body_image_before_remote_only_cover(
    client: AsyncClient,
    db_session,
    stored_media_asset,
    monkeypatch,
):
    local_body, _, _ = stored_media_asset
    local_body.role = MediaRole.BODY
    remote_cover = MediaAsset(
        content_id=local_body.content_id,
        media_type=MediaType.IMAGE,
        role=MediaRole.COVER,
        original_url="https://images.example.test/remote-cover.jpg",
        client_fetch_allowed=True,
        archive_status=MediaArchiveStatus.MISSING,
    )
    db_session.add(remote_cover)
    await db_session.commit()
    monkeypatch.setattr(settings, "media_signing_secret", SecretStr("media-secret"))

    response = await client.get(f"/api/v1/cards/{local_body.content_id}")

    assert response.status_code == 200
    assets = response.json()["media_assets"]
    assert [asset["role"] for asset in assets[:2]] == ["body", "cover"]
    assert assets[0]["sources"][0]["source_kind"] == "local_signed"


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
