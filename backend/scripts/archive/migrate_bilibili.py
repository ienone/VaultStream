import asyncio
import sys
import os

# Ensure backend path is in sys.path
sys.path.append(os.path.join(os.getcwd(), 'backend'))

from sqlalchemy import select
from app.database import AsyncSessionLocal
from app.models import Content, Platform, BilibiliContentType
from app.media_processing import store_archive_images_as_webp
from app.storage import get_storage_backend
from app.config import settings


def _get_metadata(content: Content):
    """兼容新旧字段：优先 archive_metadata，回退 raw_metadata。"""
    archive_meta = getattr(content, "archive_metadata", None)
    if isinstance(archive_meta, dict):
        return archive_meta
    raw_meta = getattr(content, "raw_metadata", None)
    if isinstance(raw_meta, dict):
        return raw_meta
    return None


def _set_metadata(content: Content, meta: dict):
    """统一写回新字段，旧库结构下回退写 raw_metadata。"""
    if hasattr(content, "archive_metadata"):
        content.archive_metadata = meta
    elif hasattr(content, "raw_metadata"):
        content.raw_metadata = meta

async def migrate_bilibili():
    storage = get_storage_backend()
    if hasattr(storage, "ensure_bucket"):
        await storage.ensure_bucket()

    async with AsyncSessionLocal() as session:
        result = await session.execute(
            select(Content).where(Content.platform == Platform.BILIBILI)
        )
        contents = result.scalars().all()
        
        count = 0
        for content in contents:
            meta = _get_metadata(content)
            if not isinstance(meta, dict):
                continue
            
            # Check if archive exists
            if "archive" in meta:
                continue
                
            print(f"Migrating Bilibili content {content.id} ({content.content_type})...")
            
            # Construct archive based on content type
            archive = None
            
            if content.content_type == BilibiliContentType.VIDEO.value:
                archive = {
                    "version": 2,
                    "type": "bilibili_video",
                    "title": meta.get('title', ''),
                    "plain_text": meta.get('desc', ''),
                    "markdown": meta.get('desc', ''),
                    "images": [{"url": meta.get('pic')}] if meta.get('pic') else [],
                    "videos": [],
                    "links": [],
                    "stored_images": [],
                    "stored_videos": []
                }
            elif content.content_type == BilibiliContentType.ARTICLE.value:
                image_urls = meta.get('image_urls', [])
                archive = {
                    "version": 2,
                    "type": "bilibili_article",
                    "title": meta.get('title', ''),
                    "plain_text": meta.get('summary', ''),
                    "markdown": meta.get('summary', ''),
                    "images": [{"url": u} for u in image_urls],
                    "links": [],
                    "stored_images": []
                }
            
            if archive:
                # Update metadata
                meta['archive'] = archive
                _set_metadata(content, meta)
                
                # Process media immediately
                if settings.enable_archive_media_processing:
                    print(f"  Processing media for {content.id}...")
                    try:
                        await store_archive_images_as_webp(
                            archive=archive,
                            storage=storage,
                            namespace="vaultstream",
                            quality=settings.archive_image_webp_quality,
                            max_images=settings.archive_image_max_count,
                        )
                        
                        # Update cover_url and media_urls
                        stored_images = archive.get("stored_images", [])
                        if stored_images:
                            local_urls = []
                            for img in stored_images:
                                u = img.get("url")
                                k = img.get("key")
                                if u:
                                    local_urls.append(u)
                                elif k:
                                    local_urls.append(f"local://{k}")
                            
                            local_urls = list(dict.fromkeys(local_urls))
                            if local_urls:
                                content.media_urls = local_urls
                                content.cover_url = local_urls[0]
                                print(f"  Updated cover_url to {content.cover_url}")
                                
                    except Exception as e:
                        print(f"  Error processing media: {e}")
                
                count += 1
        
        if count > 0:
            await session.commit()
            print(f"Successfully migrated {count} Bilibili contents")
        else:
            print("No Bilibili contents needed migration")

if __name__ == "__main__":
    asyncio.run(migrate_bilibili())
