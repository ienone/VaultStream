"""补齐已保存内容的媒体，复用持久队列，不重新解析正文或运行后处理。"""
import asyncio

from sqlalchemy import select, update
from sqlalchemy.orm import selectinload

from app.adapters.storage import get_storage_backend
from app.core.db_adapter import AsyncSessionLocal
from app.core.queue import task_queue
from app.models import Content, Task, TaskStatus
from app.models.media import MediaArchiveStatus, MediaAsset, MediaType, MediaVariant, MediaVariantKind, MediaVariantStatus
from app.media.processor import archive_media_file
from app.core.logging import logger

from app.services.config_service import ConfigService
from app.services.media_backfill import _variant_from_item
from app.services.background_task_state import (
    record_task_run_started, record_task_run_success, record_task_run_error,
)


async def enqueue_media_repair(db, content_id: int, *, asset_id: int | None = None) -> bool:
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
        MediaAsset.id == asset_id if asset_id is not None else MediaAsset.original_url.is_not(None),
    ).limit(1))
    if source is None:
        return False
    pending = await db.scalar(select(Task.id).where(
        Task.task_type == 'repair_media',
        Task.payload['content_id'].as_integer() == content_id,
        Task.payload['asset_id'].as_integer().is_(None) if asset_id is None else Task.payload['asset_id'].as_integer() == asset_id,
        Task.status.in_([TaskStatus.PENDING, TaskStatus.RUNNING]),
    ).limit(1))
    if pending is None:
        task_queue.add(db, 'repair_media', {'content_id': content_id, 'asset_id': asset_id, 'priority': 4, 'trigger': 'auto'}, run_name='media_repair')
        await db.flush()
    return True


async def repair_content_media(content_id: int, *, claimed_task: Task | None = None) -> dict:
    config = await ConfigService().get_archive_media_config()
    if not config.enabled:
        return {'skipped': True, 'reason': 'archive_disabled'}
    target_id = (claimed_task.payload or {}).get('asset_id') if claimed_task else None
    storage = get_storage_backend()
    async with AsyncSessionLocal() as db:
        content = await db.get(Content, content_id)
        if content is None or content.deleted_at is not None:
            return {'skipped': True, 'reason': 'content_deleted'}
        assets = list((await db.scalars(select(MediaAsset).where(
            MediaAsset.content_id == content_id,
        ).options(selectinload(MediaAsset.variants)).order_by(MediaAsset.id))).all())
        work = []
        for kind, enabled, limit in (
            (MediaType.IMAGE, config.images_enabled, config.image_max_count),
            (MediaType.VIDEO, config.videos_enabled, config.video_max_count),
        ):
            if not enabled:
                continue
            eligible = [asset for asset in assets if asset.media_type == kind and (asset.original_url or asset.id == target_id)]
            for asset in eligible[:limit]:
                if target_id is not None and asset.id != target_id:
                    continue
                if asset.variants and asset.archive_status == MediaArchiveStatus.READY and all(
                    v.status == MediaVariantStatus.READY for v in asset.variants
                ):
                    continue
                work.append((asset.id, asset.original_url, kind, asset.updated_at,
                             [(v.variant_kind, v.storage_key, v.status) for v in asset.variants]))

    incomplete = 0
    for asset_id, url, kind, version, versions in work:
        main_kind = MediaVariantKind.OPTIMIZED if kind == MediaType.IMAGE else MediaVariantKind.ORIGINAL_ARCHIVE
        main_key = next((key for k, key, state in versions if
                         k in (main_kind, MediaVariantKind.ORIGINAL_ARCHIVE) and state == MediaVariantStatus.READY), None)
        try:
            item, color = await archive_media_file(url, kind=kind.value, main_key=main_key,
                storage=storage, quality=config.image_webp_quality, video_max_bytes=config.video_max_bytes)
        except Exception as error:
            logger.warning("Archive asset {} failed: {}", asset_id, type(error).__name__)
            item, color = {}, None
        async with AsyncSessionLocal() as db:
            if claimed_task and not await task_queue.owns(db, claimed_task):
                raise RuntimeError('media repair task already settled')
            locked = await db.execute(update(MediaAsset).where(MediaAsset.id == asset_id,
                MediaAsset.updated_at == version, MediaAsset.content_id == content_id,
                MediaAsset.content_id.in_(select(Content.id).where(Content.deleted_at.is_(None)))
            ).values(updated_at=MediaAsset.updated_at))
            if not locked.rowcount:
                continue
            asset = await db.get(MediaAsset, asset_id, options=(selectinload(MediaAsset.variants),))
            if not item.get('stored_key'):
                asset.archive_status = MediaArchiveStatus.FAILED
                asset.last_error = 'archive_download_failed'
                incomplete += 1
            else:
                if main_key and item["stored_key"] == main_key:
                    main_kind = next(k for k, key, _ in versions if key == main_key and k != MediaVariantKind.THUMBNAIL)
                for variant_kind, field in ((main_kind, 'stored_key'), (MediaVariantKind.THUMBNAIL, 'thumb_key')):
                    key = item.get(field)
                    if not key or (field == 'thumb_key' and key == item['stored_key']):
                        continue
                    candidate = _variant_from_item(item, kind=variant_kind, key_names=(field,), default_mime=None)
                    variant = next((v for v in asset.variants if v.variant_kind == variant_kind), None)
                    if variant is None:
                        variant = MediaVariant(variant_kind=variant_kind)
                        asset.variants.append(variant)
                    if variant.storage_key and variant.storage_key != key:
                        aliases = (asset.asset_metadata or {}).get('previous_keys', [])
                        asset.asset_metadata = {**(asset.asset_metadata or {}), 'previous_keys':
                            list(dict.fromkeys([*aliases, variant.storage_key]))}
                    variant.storage_key = key
                    variant.status = MediaVariantStatus.READY
                    for field_name in ('mime_type', 'width', 'height', 'size_bytes', 'checksum'):
                        value = getattr(candidate, field_name)
                        if value is not None:
                            setattr(variant, field_name, value)
                if color and asset.role.value == "cover":
                    await db.execute(update(Content).where(Content.id == content_id).values(cover_color=color))
                asset.archive_status = MediaArchiveStatus.READY
                asset.last_error = None
            await db.commit()
    return {'content_id': content_id, 'assets': len(work), 'incomplete': incomplete}


async def process_media_repair_task(task: Task) -> None:
    run = await record_task_run_started('media_repair', run_id=task.payload.get('run_id'), content_id=task.payload['content_id'], task_db_id=task.id)
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
    finally:
        from app.core.events import event_bus
        await event_bus.publish('content_updated', {'id': task.payload['content_id']})
