import asyncio
import json
from sqlalchemy import select
from app.database import AsyncSessionLocal
from app.models import Content

async def fix_data():
    async with AsyncSessionLocal() as session:
        result = await session.execute(select(Content))
        contents = result.scalars().all()
        
        count = 0
        for content in contents:
            updated = False
            meta = content.raw_metadata
            if not isinstance(meta, dict):
                continue
                
            archive = meta.get("archive")
            if not isinstance(archive, dict):
                continue
                
            stored_images = archive.get("stored_images", [])
            if stored_images:
                local_urls = [img["url"] for img in stored_images if img.get("url")]
                if local_urls:
                    # Force update to local URLs if they differ
                    if str(content.media_urls) != str(local_urls):
                        content.media_urls = local_urls
                        updated = True
                    
                    if not content.cover_url or "pbs.twimg.com" in str(content.cover_url):
                        content.cover_url = local_urls[0]
                        updated = True
            
            # Special case for Twitter: if no cover, and we have raw_metadata images (not stored)
            if content.platform == "twitter" and not content.cover_url:
                legacy_images = archive.get("images", [])
                if legacy_images:
                    first = legacy_images[0]
                    url = first.get("url") if isinstance(first, dict) else first
                    if url:
                        content.cover_url = url
                        content.media_urls = [img.get("url") if isinstance(img, dict) else img for img in legacy_images]
                        updated = True

            if updated:
                count += 1
                print(f"Updated content {content.id} ({content.platform})")
        
        if count > 0:
            await session.commit()
            print(f"Successfully fixed {count} records")
        else:
            print("No records needed fixing")

if __name__ == "__main__":
    asyncio.run(fix_data())
