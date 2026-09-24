"""补齐已保存内容的媒体，复用持久队列，不重新解析正文或运行后处理。"""
import asyncio
from copy import deepcopy

from sqlalchemy import select, update
from sqlalchemy.orm import selectinload

from app.adapters.storage import get_storage_backend
from app.core.db_adapter import AsyncSessionLocal
from app.core.queue import task_queue
from app.models import Content, Task, TaskStatus
from app.models.media import MediaAsset, MediaType, MediaVariantStatus
from app.media.processor import store_archive_images, store_archive_videos
from app.media.references import apply_archive_media, rewrite_media_urls
from app.services.config_service import ConfigService
from app.services.media_backfill import replace_content_media_assets
from app.services.background_task_state import (
    record_task_run_started, record_task_run_success, record_task_run_error,
)


async def enqueue_media_repair(db, content_id: int) -> bool:
    config = await ConfigService().get_archive_media_config()
    kinds = ([MediaType.IMAGE] if config.images_enabled else []) + ([MediaType.VIDEO] if config.videos_enabled else [])
    if not config.enabled or not kinds:
        return False
    # Acquire the writer before checking for an existing job; concurrent reports coalesce.
    exists = await db.execute(update(Content).where(
        Content.id == content_id, Content.deleted_at.is_(None),
    ).values(updated_at=Content.updated_at))
    if not exists.rowcount:
        return False
    source = await db.scalar(select(MediaAsset.id).where(
        MediaAsset.content_id == content_id, MediaAsset.media_type.in_(kinds),
        MediaAsset.original_url.is_not(None),
    ).limit(1))
    if source is None:
        return False
    pending = await db.scalar(select(Task.id).where(
        Task.task_type == 'repair_media',
        Task.payload['content_id'].as_integer() == content_id,
        Task.status.in_([TaskStatus.PENDING, TaskStatus.RUNNING]),
    ).limit(1))
    if pending is None:
        db.add(Task(task_type='repair_media', payload={'content_id': content_id}, status=TaskStatus.PENDING))
        await db.flush()
    return True


async def repair_content_media(content_id: int, *, claimed_task: Task | None = None) -> dict:
    config = await ConfigService().get_archive_media_config()
    if not config.enabled:
        return {'skipped': True, 'reason': 'archive_disabled'}
    storage = get_storage_backend()
    async with AsyncSessionLocal() as db:
        content = await db.get(Content, content_id)
        if content is None or content.deleted_at is not None:
            return {'skipped': True, 'reason': 'content_deleted'}
        version = content.updated_at
        metadata = deepcopy(content.archive_metadata or {})
        archive_field = ('processed_archive' if not isinstance(metadata.get('archive'), dict)
                         and isinstance(metadata.get('processed_archive'), dict) else 'archive')
        archive = metadata.setdefault(archive_field, {})
        assets = list((await db.scalars(select(MediaAsset).where(
            MediaAsset.content_id == content_id,
        ).options(selectinload(MediaAsset.variants)))).all())
        bad_keys = {v.storage_key for a in assets for v in a.variants if v.status == MediaVariantStatus.FAILED}
        for asset in assets:
            if asset.media_type not in (MediaType.IMAGE, MediaType.VIDEO) or not asset.original_url:
                continue
            items = archive.setdefault(f'{asset.media_type.value}s', [])
            if not any(item.get('url') == asset.original_url for item in items):
                item = {'url': asset.original_url, 'type': asset.role.value}
                for v in asset.variants:
                    if v.variant_kind.value in ('optimized', 'original_archive'):
                        item.update(stored_key=v.storage_key, stored_content_type=v.mime_type,
                                    stored_sha256=v.checksum, stored_size=v.size_bytes,
                                    stored_width=v.width, stored_height=v.height)
                    elif v.variant_kind.value == 'thumbnail':
                        item['thumb_key'] = v.storage_key
                items.append(item)
        before = deepcopy(archive)
        for field in ('images', 'videos'):
            if (field == 'images' and not config.images_enabled) or (field == 'videos' and not config.videos_enabled):
                continue
            for item in archive.get(field) or []:
                for prefix in ('stored_', 'thumb_'):
                    if item.get(prefix + 'key') in bad_keys:
                        for key in list(item):
                            if key.startswith(prefix):
                                item.pop(key)
        await db.rollback()

    if config.images_enabled:
        await store_archive_images(archive=archive, storage=storage, namespace='vaultstream',
                                   quality=config.image_webp_quality, max_images=config.image_max_count)
    if config.videos_enabled:
        await store_archive_videos(archive=archive, storage=storage, namespace='vaultstream',
                                   max_videos=config.video_max_count, max_bytes=config.video_max_bytes)

    async with AsyncSessionLocal() as db:
        if claimed_task is not None and not await task_queue.owns(db, claimed_task):
            raise RuntimeError('media repair task already settled')
        await db.execute(update(Content).where(Content.id == content_id).values(updated_at=Content.updated_at))
        content = await db.get(Content, content_id)
        if content is None or content.deleted_at is not None or content.updated_at != version:
            await db.rollback()
            return {'skipped': True, 'reason': 'content_changed'}
        # A re-download may produce a different content hash; replace only known old references.
        mapping = {}
        for field in ('images', 'videos'):
            for old, new in zip(before.get(field) or [], archive.get(field) or []):
                if old.get('stored_key') and new.get('stored_key'):
                    mapping[f"local://{old['stored_key']}"] = f"local://{new['stored_key']}"
        content.body = rewrite_media_urls(content.body, mapping)
        content.cover_url = mapping.get(content.cover_url, content.cover_url)
        content.author_avatar_url = mapping.get(content.author_avatar_url, content.author_avatar_url)
        content.media_urls = [mapping.get(url, url) for url in content.media_urls or []]
        content.rich_payload = deepcopy(content.rich_payload)
        apply_archive_media(content, archive)
        content.archive_metadata = metadata
        kinds = ({MediaType.IMAGE} if config.images_enabled else set()) | ({MediaType.VIDEO} if config.videos_enabled else set())
        updated = await replace_content_media_assets(db, content, storage, source='media_repair', media_types=kinds)
        missing = sum(a.archive_status.value != 'ready' for a in updated
                      if a.original_url and ((a.media_type == MediaType.IMAGE and config.images_enabled)
                                             or (a.media_type == MediaType.VIDEO and config.videos_enabled)))
        await db.commit()
        return {'content_id': content_id, 'assets': len(updated), 'incomplete': missing}


async def process_media_repair_task(task: Task) -> None:
    run = await record_task_run_started('media_repair', content_id=task.payload['content_id'], task_db_id=task.id)
    try:
        result = await asyncio.wait_for(repair_content_media(task.payload['content_id'], claimed_task=task),
                                        timeout=task_queue.EXECUTION_TIMEOUT.total_seconds())
        if result.get('incomplete'):
            raise RuntimeError(f"{result['incomplete']} media assets remain incomplete")
        if not await task_queue.mark_complete(task):
            raise RuntimeError('media repair task already settled')
        await record_task_run_success('media_repair', run['run_id'], **result)
    except (Exception, asyncio.CancelledError) as error:
        await task_queue.mark_failed(task, reason=str(error) or 'Media repair cancelled')
        await record_task_run_error('media_repair', run['run_id'], error)
        if isinstance(error, asyncio.CancelledError):
            raise
