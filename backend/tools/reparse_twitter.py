import asyncio
import sys
from sqlalchemy import select, and_
from app.database import init_db, AsyncSessionLocal
from app.models import Content, Platform, ContentStatus
from app.queue import task_queue
from app.logging import logger

async def main():
    print("Initializing database...")
    await init_db()
    
    print("Initializing queue...")
    await task_queue.connect()
    
    async with AsyncSessionLocal() as session:
        # 查找所有 Twitter/X 内容
        print("Querying Twitter content...")
        result = await session.execute(
            select(Content).where(
                and_(
                    Content.platform == Platform.TWITTER,
                    # 可以选择只重试特定状态的，或者全部重试
                    # Content.status == ContentStatus.PARSE_SUCCESS
                )
            )
        )
        contents = result.scalars().all()
        
        print(f"Found {len(contents)} Twitter contents.")
        
        count = 0
        for content in contents:
            # 入队重试
            # Reset status to UNPROCESSED to be safe?
            # Or just enqueue 'parse' task which will handle it.
            # Usually enqueue is enough.
            
            task_payload = {
                'content_id': content.id,
                'action': 'parse',
                'force_update': True # Custom flag if needed, usually parse overwrites
            }
            
            await task_queue.enqueue(task_payload)
            count += 1
            if count % 10 == 0:
                print(f"Enqueued {count} tasks...")
                
        print(f"Finished. Enqueued {count} tasks.")

    await task_queue.disconnect()

if __name__ == "__main__":
    if sys.platform == 'win32':
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    asyncio.run(main())
