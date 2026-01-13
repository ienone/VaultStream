import asyncio
import sys
import os

sys.path.append(os.path.join(os.getcwd(), 'backend'))

from app.worker import worker
from app.database import init_db

async def reparse():
    await init_db()
    # Content ID 20 is the question that failed
    print("Triggering re-parse for Content 20...")
    await worker.retry_parse(content_id=20, force=True)
    print("Done.")

if __name__ == "__main__":
    asyncio.run(reparse())
