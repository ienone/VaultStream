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
            stored_videos = archive.get("stored_videos", [])
            
            local_urls = []
            
            # 1. Add images
            if stored_images:
                for img in stored_images:
                    u = img.get("url")
                    k = img.get("key")
                    if u:
                        local_urls.append(u)
                    elif k:
                        local_urls.append(f"local://{k}")
            
            # 2. Add videos
            if stored_videos:
                for vid in stored_videos:
                    u = vid.get("url")
                    k = vid.get("key")
                    if u:
                        local_urls.append(u)
                    elif k:
                        local_urls.append(f"local://{k}")

            if local_urls:
                # Deduplicate while preserving order
                local_urls = list(dict.fromkeys(local_urls))

                # Force update to local URLs if they differ
                if str(content.media_urls) != str(local_urls):
                    print(f"Updating media_urls for {content.id}: {content.media_urls} -> {local_urls}")
                    content.media_urls = local_urls
                    updated = True
                
                # If current cover_url is NOT in the local_urls list, and we have local URLs, 
                # we should probably switch to the first local URL.
                if not content.cover_url or content.cover_url not in local_urls:
                    # Only replace if the current cover_url looks like a remote URL or is missing
                    if not content.cover_url or content.cover_url.startswith("http"):
                         # Only replace if it's NOT a localhost URL (which starts with http but is local)
                         # Actually, if we have local_urls, we generally prefer them.
                         # But be careful if cover_url is a specific one not in the list?
                         # For now, simplistic check: if it's remote, swap it.
                         if not content.cover_url or "localhost" not in content.cover_url:
                             print(f"Updating cover_url for {content.id}: {content.cover_url} -> {local_urls[0]}")
                             content.cover_url = local_urls[0]
                             updated = True
            
            # Special case fallback
            if not content.cover_url and not stored_images and not stored_videos:
                legacy_images = archive.get("images", [])
                if legacy_images:
                    first = legacy_images[0]
                    url = first.get("url") if isinstance(first, dict) else first
                    if url:
                         print(f"Restoring remote cover_url for {content.id}: {url}")
                         content.cover_url = url
                         updated = True

            if updated:
                count += 1
        
        if count > 0:
            await session.commit()
            print(f"Successfully fixed {count} records")
        else:
            print("No records needed fixing")

if __name__ == "__main__":
    asyncio.run(fix_data())
