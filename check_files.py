import asyncio
import os
import sys
from sqlalchemy import select
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

# Adjust path to include app
sys.path.append(os.getcwd())
sys.path.append(os.path.join(os.getcwd(), 'backend'))

from backend.app.models import Content, ContentStatus
from backend.app.config import settings

async def check_files():
    # Fix DB path for this script context: project_root/backend/data/vaultstream.db
    db_path = os.path.join(os.getcwd(), 'backend', 'data', 'vaultstream.db')
    if not os.path.exists(db_path):
        print(f"Error: DB file not found at {db_path}")
        return

    db_url = f"sqlite+aiosqlite:///{db_path}"
    engine = create_async_engine(db_url)
    AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with AsyncSessionLocal() as session:
        # Fetch ALL pulled contents to be thorough
        result = await session.execute(
            select(Content).where(Content.status == ContentStatus.PULLED)
        )
        contents = result.scalars().all()

        print(f"Checking {len(contents)} contents...")
        
        missing_count = 0
        total_files = 0
        contents_with_missing = set()

        for content in contents:
            if not content.raw_metadata or 'archive' not in content.raw_metadata:
                continue

            archive = content.raw_metadata['archive']
            stored_images = archive.get('stored_images', [])

            for img in stored_images:
                total_files += 1
                key = img.get('key')
                if not key:
                    continue

                # Construct local path from key
                # Key typically starts with "vaultstream/blobs/..."
                # storage_local_root from .env is "./data/media", but wait...
                # let's check what config.settings actually says at runtime.
                # If .env says STORAGE_LOCAL_ROOT=./data/media, that's inside backend/data/media?
                
                # We will check both "data/storage" (default) and "data/media" just in case.
                
                # Assume standard structure: backend/data/storage/ + key
                # Note: The key itself usually contains 'vaultstream/blobs/...'
                
                # Check path 1: backend/data/storage/key
                full_path_1 = os.path.join(os.getcwd(), 'backend', 'data', 'storage', key)
                
                # Check path 2: backend/data/media/key (if config changed)
                full_path_2 = os.path.join(os.getcwd(), 'backend', 'data', 'media', key)

                if os.path.exists(full_path_1):
                    continue
                elif os.path.exists(full_path_2):
                    continue
                else:
                    # Missing in both potential locations
                    # Only print first few to avoid spam
                    if missing_count < 5:
                         print(f"[MISSING] Content {content.id} Key: {key}")
                    missing_count += 1
                    contents_with_missing.add(content.id)
        
        print("-" * 30)
        print(f"Total files checked: {total_files}")
        print(f"Total missing files: {missing_count}")
        print(f"Contents with missing files: {len(contents_with_missing)}")
        
        if len(contents_with_missing) > 0:
            print(f"IDs: {list(contents_with_missing)[:20]}...")

if __name__ == "__main__":
    asyncio.run(check_files())
