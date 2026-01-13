import asyncio
import sys
import os
from bs4 import BeautifulSoup
from markdownify import markdownify as md

# Ensure backend path is in sys.path
sys.path.append(os.path.join(os.getcwd(), 'backend'))

from sqlalchemy import select
from app.database import AsyncSessionLocal
from app.models import Content, Platform
from app.media_processing import store_archive_images_as_webp
from app.storage import get_storage_backend
from app.config import settings
from app.adapters.zhihu_parser.base import preprocess_zhihu_html, extract_images

async def migrate_zhihu():
    storage = get_storage_backend()
    if hasattr(storage, "ensure_bucket"):
        await storage.ensure_bucket()

    async with AsyncSessionLocal() as session:
        result = await session.execute(
            select(Content).where(Content.platform == Platform.ZHIHU)
        )
        contents = result.scalars().all()
        
        count = 0
        for content in contents:
            if not content.raw_metadata or not isinstance(content.raw_metadata, dict):
                continue
            meta = dict(content.raw_metadata)

            
            # Check if archive already exists? 
            # The user said "re-parse", implying existing might be broken or we want to force it.
            # But if I just added the logic, existing ones DEFINITELY don't have it (or have it empty?).
            # Let's force update if 'archive' is missing OR if we want to refresh images.
            # For now, let's just do it.
            
            print(f"Migrating Zhihu content {content.id} ({content.content_type})...")
            
            # Extract content HTML
            content_html = meta.get('content', '') or meta.get('contentHtml', '')
            if isinstance(content_html, list):
                 # Handle list content (rare for simple migration, maybe Pin?)
                 content_html = "" 
            
            if not content_html and content.content_type != 'pin':
                print(f"  Warning: No content HTML found for {content.id}")
                continue

            # Process HTML
            processed_html = preprocess_zhihu_html(content_html) if isinstance(content_html, str) else ""
            
            # Extract images
            media_urls = extract_images(processed_html)
            
            # Pin fallback strategy for images
            if content.content_type == 'pin' and 'content' in meta and isinstance(meta['content'], list):
                 for item in meta['content']:
                    if isinstance(item, dict) and item.get('type') == 'image':
                        u = item.get('url')
                        if u: media_urls.append(u)
            
            media_urls = list(dict.fromkeys(media_urls))
            
            # Markdown & Plain Text
            markdown_content = md(processed_html, heading_style="ATX") if processed_html else ""
            plain_text = BeautifulSoup(processed_html, 'html.parser').get_text("\n") if processed_html else (meta.get('excerpt', '') or '')

            # Construct archive
            title = meta.get('title', '')
            if not title and content.content_type == 'answer':
                 q_title = meta.get('associated_question', {}).get('title', '')
                 title = f"回答：{q_title}" if q_title else f"知乎回答 {meta.get('id')}"
            
            archive_images = [{"url": u} for u in media_urls]
            author_data = meta.get('author')
            author_avatar = author_data.get('avatarUrl') if isinstance(author_data, dict) else None
            if author_avatar:
                archive_images.append({"url": author_avatar, "type": "avatar"})

            archive = {
                "version": 2,
                "type": f"zhihu_{content.content_type}",
                "title": title,
                "plain_text": plain_text,
                "markdown": markdown_content,
                "images": archive_images,
                "links": [],
                "stored_images": [],
                "stored_videos": []
            }

            
            # Update metadata
            meta['archive'] = archive
            content.raw_metadata = meta 
            
            # Process media immediately
            if settings.enable_archive_media_processing:
                print(f"  Processing media for {content.id} (found {len(media_urls)} images)...")
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
                            # For cover, try to match original logic or just take first
                            # Original: cover_url=meta.get('thumbnail') or media_urls[0]
                            # We should prefer local version of that thumbnail if possible, 
                            # or just first local image.
                            # Simpler: just set cover to first local image if we have one.
                            content.cover_url = local_urls[0]
                            print(f"  Updated cover_url to {content.cover_url}")
                            
                except Exception as e:
                    print(f"  Error processing media: {e}")
            
            count += 1
        
        if count > 0:
            await session.commit()
            print(f"Successfully migrated {count} Zhihu contents")
        else:
            print("No Zhihu contents needed migration")

if __name__ == "__main__":
    asyncio.run(migrate_zhihu())
