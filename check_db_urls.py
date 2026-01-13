import asyncio
import os
import sys
from sqlalchemy import select
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

sys.path.append(os.getcwd())
sys.path.append(os.path.join(os.getcwd(), 'backend'))

from backend.app.models import Content, ContentStatus
from backend.app.config import settings

async def check_urls():
    # Force use of correct DB path
    db_path = os.path.join(os.getcwd(), 'backend', 'data', 'vaultstream.db')
    db_url = f"sqlite+aiosqlite:///{db_path}"
    engine = create_async_engine(db_url)
    AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with AsyncSessionLocal() as session:
        # Fetch a few pulled contents
        result = await session.execute(
            select(Content).where(Content.status == ContentStatus.PULLED).limit(5)
        )
        contents = result.scalars().all()

        print(f"Checking {len(contents)} contents...")
        
        for content in contents:
            print(f"Content ID: {content.id}")
            print(f"  Title: {content.title}")
            print(f"  Cover URL: {content.cover_url}")
            
            # Check raw_metadata for stored info
            if content.raw_metadata and 'archive' in content.raw_metadata:
                archive = content.raw_metadata['archive']
                stored = archive.get('stored_images', [])
                print(f"  Stored Images Count: {len(stored)}")
                if stored:
                    first = stored[0]
                    print(f"  First Stored Image Key: {first.get('key')}")
                    print(f"  First Stored Image URL: {first.get('url')}")
            else:
                print("  No archive metadata")
            print("-" * 20)

if __name__ == "__main__":
    asyncio.run(check_urls())
