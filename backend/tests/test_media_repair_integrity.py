"""Media repair must preserve saved content and honour archive policy."""
from io import BytesIO
from types import SimpleNamespace
from uuid import uuid4

import pytest
from PIL import Image
from sqlalchemy import select

from app.adapters.storage import get_storage_backend
from app.core.db_adapter import AsyncSessionLocal
from app.core.safe_fetch import SafeFetchResult
from app.media import processor
from app.models import Content, ContentStatus, Platform, Task, TaskStatus
from app.services import media_repair
from app.services.media_backfill import replace_content_media_assets
from app.services.config_service import ConfigService
from app.services.media_manifest import build_media_manifest
from app.schemas.media import MediaPurpose
from app.tasks.runner import TaskWorker


@pytest.fixture
async def repairable(monkeypatch):
    config = SimpleNamespace(enabled=True, images_enabled=True, videos_enabled=False,
                             image_webp_quality=80, image_max_count=10, video_max_count=1, video_max_bytes=10000)
    async def archive_config(self):
        return config
    monkeypatch.setattr(ConfigService, 'get_archive_media_config', archive_config)
    output = BytesIO()
    Image.new('RGB', (400, 400), 'blue').save(output, 'PNG')
    url = f'https://example.test/{uuid4().hex}.png'
    response = SafeFetchResult(url=url, status_code=200, headers={'content-type':'image/png'}, content=output.getvalue())
    calls = []
    async def download(*args, **kwargs):
        calls.append(1)
        return response
    monkeypatch.setattr(processor, '_download', download)
    storage = get_storage_backend()
    archive = {'images':[{'url':url,'type':'cover'}]}
    await processor.store_archive_images(archive=archive, storage=storage, namespace='vaultstream')
    async with AsyncSessionLocal() as db:
        content = Content(platform=Platform.UNIVERSAL, url=url, status=ContentStatus.PARSE_SUCCESS,
                          title='Manual title', body='Manual body', manual_edit_fields=['title','body'],
                          cover_url=f"local://{archive['images'][0]['stored_key']}", archive_metadata={'archive':archive})
        db.add(content)
        await db.flush()
        assets = await replace_content_media_assets(db, content, storage, source='test')
        await db.commit()
        asset = assets[0]
        variant = next(v for v in asset.variants if v.variant_kind.value == 'optimized')
        initial = build_media_manifest(asset, purpose=MediaPurpose.DETAIL, base_url='http://test', now=1000)
        result = (content.id, asset.id, variant.id, variant.storage_key, initial.sources[0].cache_key)
    calls.clear()
    return config, storage, calls, result


@pytest.mark.parametrize('corrupt', [False, True])
async def test_failure_deduplicates_durable_repair_and_preserves_content(client, repairable, corrupt):
    config, storage, calls, (content_id, asset_id, variant_id, key, cache_key) = repairable
    if corrupt:
        await storage.put_bytes(key=key, data=b'broken', content_type='image/png')
    else:
        await storage.delete(key=key)
    payload = {'variant_id':variant_id, 'error_code':'media_decode_failed' if corrupt else 'media_blob_missing'}
    for _ in range(2):
        response = await client.post(f'/api/v1/media/assets/{asset_id}/failures', json=payload)
        assert response.status_code == 200, response.text
        assert response.json()['repair_queued']
    async with AsyncSessionLocal() as db:
        jobs = (await db.scalars(select(Task).where(Task.task_type=='repair_media', Task.payload['content_id'].as_integer()==content_id))).all()
        assert len(jobs) == 1
        task = jobs[0]; task.status = TaskStatus.RUNNING
        await db.commit()
    await TaskWorker().process_task(task)
    assert len(calls) == 1
    with Image.open(BytesIO(await storage.get_bytes(key))) as image:
        image.verify()
    async with AsyncSessionLocal() as db:
        content = await db.get(Content, content_id)
        assert (content.title, content.body, content.status) == ('Manual title','Manual body',ContentStatus.PARSE_SUCCESS)
        assert (await db.get(Task,task.id)).status == TaskStatus.COMPLETED
    manifest = (await client.get(f'/api/v1/media/assets/{asset_id}/manifest')).json()
    assert manifest['sources'][0]['variant_id'] == variant_id
    assert manifest['sources'][0]['cache_key'] == cache_key


async def test_disabled_archive_does_not_enqueue_or_download(repairable):
    config, storage, calls, (content_id, *_rest) = repairable
    config.enabled = False
    async with AsyncSessionLocal() as db:
        assert not await media_repair.enqueue_media_repair(db, content_id)
    assert (await media_repair.repair_content_media(content_id))['reason'] == 'archive_disabled'
    assert calls == []


async def test_repair_does_not_overwrite_edit_during_download(repairable, monkeypatch):
    config, storage, calls, (content_id, _asset, _variant, key, _cache) = repairable
    await storage.delete(key=key)
    download = processor._download
    async def concurrent_edit(*args, **kwargs):
        async with AsyncSessionLocal() as db:
            content = await db.get(Content, content_id)
            content.body = 'Edited during download'
            await db.commit()
        return await download(*args, **kwargs)
    monkeypatch.setattr(processor, '_download', concurrent_edit)
    result = await media_repair.repair_content_media(content_id)
    assert result['reason'] == 'content_changed'
    async with AsyncSessionLocal() as db:
        assert (await db.get(Content, content_id)).body == 'Edited during download'


async def test_already_parsed_content_queues_only_media_work(repairable):
    from app.tasks.parsing import ContentParser
    config, storage, calls, (content_id, *_rest) = repairable
    result = await ContentParser().execute_parse(content_id)
    assert result.skipped
    async with AsyncSessionLocal() as db:
        jobs = (await db.scalars(select(Task).where(Task.payload['content_id'].as_integer()==content_id))).all()
        assert [job.task_type for job in jobs] == ['repair_media']
    assert calls == []


async def test_image_repair_preserves_disabled_video_state(repairable):
    from app.models.media import MediaAsset, MediaType, MediaRole, MediaArchiveStatus, MediaVariant, MediaVariantKind, MediaVariantStatus
    config, storage, calls, (content_id, *_rest) = repairable
    async with AsyncSessionLocal() as db:
        video = MediaAsset(content_id=content_id, media_type=MediaType.VIDEO, role=MediaRole.BODY,
                           original_url='https://example.test/video.mp4', archive_status=MediaArchiveStatus.FAILED,
                           variants=[MediaVariant(variant_kind=MediaVariantKind.ORIGINAL_ARCHIVE,
                                      storage_key='missing-video.mp4',status=MediaVariantStatus.FAILED)])
        db.add(video); await db.commit(); video_id=video.id
    await media_repair.repair_content_media(content_id)
    async with AsyncSessionLocal() as db:
        video = await db.get(MediaAsset, video_id)
        assert video.archive_status == MediaArchiveStatus.FAILED
        assert video.original_url == 'https://example.test/video.mp4'
