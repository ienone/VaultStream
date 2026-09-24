"""媒体引用只能指向已发布对象，并发写入不得破坏共享文件。"""
import asyncio
from io import BytesIO
from types import SimpleNamespace
from unittest.mock import AsyncMock

import httpx
import pytest
from PIL import Image

from app.adapters.storage import LocalStorageBackend
from app.core.safe_fetch import SafeFetchResult
from app.media import processor
from app.media.references import apply_archive_media


def image_bytes():
    out = BytesIO()
    Image.effect_noise((600, 400), 32).convert("RGB").save(out, format="PNG")
    return out.getvalue()


def mock_download(monkeypatch, data, kind):
    monkeypatch.setattr(processor.ConfigService, "get_http_proxy", AsyncMock(return_value=None))
    fetch = AsyncMock(return_value=SafeFetchResult(
        url="https://fixture.invalid/media", status_code=200,
        headers=httpx.Headers({"content-type": f"{kind}/" + ("png" if kind == "image" else "mp4")}),
        content=data,
    ))
    monkeypatch.setattr(processor, "safe_client_get", fetch)
    return fetch


@pytest.mark.parametrize("kind", ["image", "video"])
async def test_failed_storage_never_publishes_local_reference(tmp_path, monkeypatch, kind):
    source = "https://fixture.invalid/a%2Fb?sig=a%26b%3Dc"
    fetch = mock_download(monkeypatch, image_bytes() if kind == "image" else b"video", kind)
    storage = LocalStorageBackend(str(tmp_path))
    monkeypatch.setattr(storage, "put_bytes", AsyncMock(side_effect=OSError("disk full")))
    archive = {f"{kind}s": [{"url": source, "stored_key": "missing.webp"}],
               "markdown": "![media](local://missing.webp)"}
    store = processor.store_archive_images if kind == "image" else processor.store_archive_videos
    await store(archive=archive, storage=storage, namespace="test")
    assert f"stored_{kind}s" not in archive
    assert "stored_key" not in archive[f"{kind}s"][0]
    assert archive["markdown"] == f"![media]({source})"
    assert fetch.await_count == 1  # 落盘失败不能触发重复下载。
    assert fetch.call_args.args[1] == source
    assert not list(tmp_path.rglob("*"))


async def test_missing_file_recovers_and_repeated_urls_reuse_result(tmp_path, monkeypatch, db_session):
    from app.models import Content, Platform
    from app.models.media import MediaVariantKind
    from app.services.media_backfill import replace_content_media_assets

    source = "https://fixture.invalid/photo.png"
    data = image_bytes()
    fetch = mock_download(monkeypatch, data, "image")
    storage = LocalStorageBackend(str(tmp_path))
    archive = {"images": [{"url": source, "stored_key": "missing.webp"},
                           {"url": source, "type": "cover"}],
               "markdown": f"![one](local://missing.webp) ![two]({source})"}
    await processor.store_archive_images(archive=archive, storage=storage, namespace="test")
    key = archive["images"][0]["stored_key"]
    assert key == archive["images"][1]["stored_key"]
    assert fetch.await_count == 1
    assert archive["markdown"].count(f"local://{key}") == 2
    assert len(await storage.get_bytes(key)) <= len(data)
    thumb = archive["images"][0]["thumb_key"]
    await storage.delete(key=thumb)
    archive["images"][0]["stored_key"] = "missing-again.webp"
    await processor.store_archive_images(archive=archive, storage=storage, namespace="test")
    assert fetch.await_count == 1
    assert await storage.exists(key=archive["images"][0]["thumb_key"])
    assert "stored_images" not in archive
    content = Content(url="https://fixture.invalid/media-integrity", platform=Platform.UNIVERSAL,
                      archive_metadata={"archive": archive}, media_urls=[])
    db_session.add(content)
    await db_session.flush()
    assets = await replace_content_media_assets(db_session, content, storage, source="parse")
    for asset in assets:
        for variant in asset.variants:
            blob = await storage.get_bytes(variant.storage_key)
            with Image.open(BytesIO(blob)) as actual:
                assert variant.mime_type == Image.MIME[actual.format]
                assert (variant.width, variant.height) == actual.size
            assert variant.size_bytes == len(blob)
            if variant.variant_kind == MediaVariantKind.THUMBNAIL:
                assert max(variant.width, variant.height) <= 300


async def test_proxy_preserves_signed_url_after_query_decoding(tmp_path, monkeypatch, client):
    from fastapi.responses import StreamingResponse
    from app.routers import media

    source = "https://fixture.invalid/a%2Fb?sig=a%26b%3Dc"
    monkeypatch.setattr(media, "_is_safe_url", lambda _: True)
    monkeypatch.setattr(media, "_proxy_cache_hit_response", AsyncMock(return_value=None))
    fetch = AsyncMock(return_value=StreamingResponse(iter([b"image"]), media_type="image/png"))
    monkeypatch.setattr(media, "_fetch_proxy_image_response", fetch)
    response = await client.get("/api/v1/proxy/image", params={"url": source})
    assert response.status_code == 200
    assert fetch.call_args.kwargs["url"] == source


async def test_concurrent_atomic_writes_do_not_share_temporary_files(tmp_path):
    storage = LocalStorageBackend(str(tmp_path))
    data = image_bytes()
    await asyncio.gather(*(storage.put_bytes(key="shared/image.png", data=data,
                                           content_type="image/png") for _ in range(8)))
    assert await storage.get_bytes("shared/image.png") == data
    assert not list(tmp_path.rglob("*.tmp"))


def test_partial_archive_preserves_remote_media_and_exact_url_identity():
    photo = "https://fixture.invalid/photo"
    larger = photo + "?sig=a%26b"
    video = "https://fixture.invalid/video"
    record = SimpleNamespace(body=f"![one]({photo}) ![two]({larger})",
                             media_urls=[photo, larger, video], cover_url=photo,
                             author_avatar_url=None, rich_payload=None)
    apply_archive_media(record, {"images": [{"url": photo, "stored_key": "photo.webp"}]})
    assert record.media_urls == ["local://photo.webp", larger, video]
    assert record.body == f"![one](local://photo.webp) ![two]({larger})"
    assert record.cover_url == "local://photo.webp"


async def test_cover_edits_and_reparse_preserve_asset_identity(db_session, monkeypatch, tmp_path):
    from sqlalchemy import select
    from app.models import Content, Platform
    from app.models.media import MediaAsset, MediaRole, MediaType, MediaVariant, MediaVariantKind, MediaVariantStatus
    from app.services.content_service import ContentService
    from app.services.media_backfill import replace_content_media_assets
    from app.services.media_manifest import build_content_media_manifests
    from app.schemas.media import MediaPurpose

    old, new = 'https://fixture.invalid/old.jpg', 'https://fixture.invalid/new.jpg'
    content = Content(platform=Platform.UNIVERSAL, url='https://fixture.invalid/cover-edit', cover_url=old,
                      archive_metadata={'archive': {'images': [{'url': old, 'type': 'cover'}, {'url': new}]}})
    db_session.add(content)
    await db_session.flush()
    old_asset = MediaAsset(content_id=content.id, media_type=MediaType.IMAGE, role=MediaRole.COVER,
                           position=0, original_url=old, variants=[MediaVariant(variant_kind=MediaVariantKind.OPTIMIZED,
                           storage_key='old.webp', status=MediaVariantStatus.READY)])
    new_asset = MediaAsset(content_id=content.id, media_type=MediaType.IMAGE, role=MediaRole.BODY,
                           position=0, original_url=new)
    document = MediaAsset(content_id=content.id, media_type=MediaType.DOCUMENT, role=MediaRole.ATTACHMENT,
                          position=0, original_url='https://fixture.invalid/file.pdf')
    db_session.add_all([old_asset, new_asset, document]); await db_session.commit()
    old_id, new_id, document_id = old_asset.id, new_asset.id, document.id
    monkeypatch.setattr('app.media.color.extract_cover_color', AsyncMock(return_value=None))
    service = ContentService(db_session)
    await service.update_content(content.id, {'cover_url':new})
    manifests = await build_content_media_manifests(db_session,[content.id],purpose=MediaPurpose.CARD,base_url='http://test')
    assert manifests[content.id][0].id == new_id  # Explicit cover beats the old cached image.
    assert await db_session.get(MediaAsset, document_id) is not None
    content.parse_candidate={'fields':{'cover_url':old}}
    await db_session.commit()
    await service.resolve_parse_candidate(content.id, field='cover_url',action='accept_parsed')
    assert (await db_session.get(MediaAsset,old_id)).role == MediaRole.COVER
    assert (await db_session.get(MediaAsset,new_id)).role == MediaRole.BODY
    # A full parse may drop an absent document, but reuses the explicitly identified images.
    await replace_content_media_assets(db_session,content,LocalStorageBackend(str(tmp_path)),source='parse')
    await db_session.commit()
    assert (await db_session.get(MediaAsset,old_id)).role == MediaRole.COVER
    assert (await db_session.get(MediaAsset,new_id)).role == MediaRole.BODY
