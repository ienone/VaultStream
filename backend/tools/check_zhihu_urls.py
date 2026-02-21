import asyncio
import sys
import os

sys.path.append(os.path.join(os.getcwd(), 'backend'))

from sqlalchemy import select
from app.database import AsyncSessionLocal
from app.models import Content, Platform

async def check_zhihu():
    async with AsyncSessionLocal() as session:
        result = await session.execute(
            select(Content).where(Content.platform == Platform.ZHIHU)
        )
        contents = result.scalars().all()
        
        for content in contents:
            print(f"Content ID: {content.id} ({content.content_type})")
            print(f"  Title: {content.title}")
            print(f"  Cover URL: {content.cover_url}")
            if content.archive_metadata and 'archive' in content.archive_metadata:
                archive = content.archive_metadata['archive']
                stored = archive.get('stored_images', [])
                print(f"  Stored Images: {len(stored)}")
                if stored:
                    print(f"  First Stored URL: {stored[0].get('url')}")
            else:
                print("  No archive metadata")
            print("-" * 20)

if __name__ == "__main__":
    asyncio.run(check_zhihu())
