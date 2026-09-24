"""Archiving selected images must not discard a post's unarchived video."""
from types import SimpleNamespace
from uuid import uuid4
from unittest.mock import AsyncMock

from app.models import Content, ContentStatus, Platform, LayoutType
from app.tasks.discovery_sync import DiscoverySyncTask


async def test_image_archiving_preserves_video_and_media_types(db_session, monkeypatch):
    photo, video = 'https://fixture.invalid/photo', 'https://fixture.invalid/video'
    url = f'https://fixture.invalid/post/{uuid4()}'
    content = Content(platform=Platform.UNIVERSAL, url=url, canonical_url=url,
        status=ContentStatus.PARSE_SUCCESS, layout_type=LayoutType.VIDEO,
        media_urls=[photo, video], cover_url=photo,
        archive_metadata={'archive': {'images':[{'url':photo}], 'videos':[{'url':video}]}})
    db_session.add(content)
    await db_session.commit()
    config = SimpleNamespace(enabled=True, images_enabled=True, videos_enabled=False,
        image_webp_quality=80, image_max_count=10)
    monkeypatch.setattr('app.tasks.discovery_sync.ConfigService.get_archive_media_config', AsyncMock(return_value=config))
    monkeypatch.setattr('app.tasks.discovery_sync.get_storage_backend', lambda: SimpleNamespace())
    async def archive_images(*, archive, **kwargs):
        assert [entry['url'] for entry in archive['images']] == [photo]
        archive['images'][0]['stored_key'] = 'fixture/photo.webp'
    monkeypatch.setattr('app.tasks.discovery_sync.store_archive_images', archive_images)
    video_store = AsyncMock()
    monkeypatch.setattr('app.tasks.discovery_sync.store_archive_videos', video_store)
    await DiscoverySyncTask()._archive_discovery_media(db_session,[content.id])
    await db_session.refresh(content)
    assert content.media_urls == ['local://fixture/photo.webp',video]
    assert content.cover_url == 'local://fixture/photo.webp'
    assert content.archive_metadata['archive']['videos'] == [{'url':video}]
    video_store.assert_not_awaited()
