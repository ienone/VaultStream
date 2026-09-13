"""Reparsing the same media must preserve user-owned playback bookmarks."""
from sqlalchemy import select
from app.adapters.storage import get_storage_backend
from app.models import Content, Platform
from app.models.media import MediaBookmark
from app.services.media_backfill import replace_content_media_assets

async def test_reparse_preserves_bookmark_for_same_video(db_session):
    content = Content(url='https://example.com/reparse-identity', platform=Platform.UNIVERSAL,
        archive_metadata={'archive': {'videos': [{'url': 'https://example.com/stable.mp4', 'duration_ms': 90000, 'stored_key': 'identity-video.mp4'}]}},
        media_urls=[])
    db_session.add(content)
    await db_session.flush()
    assets = await replace_content_media_assets(db_session, content, get_storage_backend(), source='parse')
    asset_id = assets[0].id
    variant_id = assets[0].variants[0].id
    bookmark = MediaBookmark(content_id=content.id, media_asset_id=asset_id, position_ms=15000, note='用户笔记')
    db_session.add(bookmark)
    await db_session.commit()
    bookmark_id = bookmark.id
    content.archive_metadata = {'archive': {'videos': [{'url': 'https://example.com/stable.mp4', 'duration_ms': 90000}]}}
    reparsed = await replace_content_media_assets(db_session, content, get_storage_backend(), source='parse')
    await db_session.commit()
    assert reparsed[0].variants[0].id == variant_id
    # Read from SQL rather than the identity map: ON DELETE CASCADE is the risk.
    row = (await db_session.execute(select(MediaBookmark.id, MediaBookmark.media_asset_id, MediaBookmark.note)
        .where(MediaBookmark.id == bookmark_id))).one_or_none()
    assert row is not None
    assert row.media_asset_id == asset_id
    assert row.note == '用户笔记'

async def test_platform_media_identity_survives_cdn_rotation_and_binds_only_own_chunks(db_session):
    content = Content(url='https://example.com/cdn-rotation', platform=Platform.UNIVERSAL,
        archive_metadata={'archive': {'videos': [{'source_identity': 'bilibili:fixture:123',
            'url': 'https://cdn.example.com/one.mp4', 'duration_ms': 90000}]}}, media_urls=[],
        rich_payload={'chunks': [{'source_identity': 'bilibili:fixture:123', 'segment_type': 'chapter',
            'start_seconds': 0, 'end_seconds': 30, 'title': '章节'},
            {'source_identity': 'bilibili:other:999', 'media_asset_id': 999}]})
    db_session.add(content)
    await db_session.flush()
    first = await replace_content_media_assets(db_session, content, get_storage_backend(), source='parse')
    first_id = first[0].id
    assert content.rich_payload['chunks'][0]['media_asset_id'] == first_id
    assert content.rich_payload['chunks'][1]['media_asset_id'] is None
    db_session.add(MediaBookmark(content_id=content.id, media_asset_id=first_id, position_ms=15000, note='保留'))
    await db_session.commit()
    content.archive_metadata = {'archive': {'videos': [{'source_identity': 'bilibili:fixture:123',
        'url': 'https://another.example.com/two.mp4', 'duration_ms': 90000}]}}
    second = await replace_content_media_assets(db_session, content, get_storage_backend(), source='parse')
    await db_session.commit()
    assert second[0].id == first_id
    assert await db_session.scalar(select(MediaBookmark.note).where(MediaBookmark.media_asset_id == first_id)) == '保留'
