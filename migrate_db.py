
import asyncio
from sqlalchemy import text
from app.database import engine

async def migrate():
    async with engine.begin() as conn:
        print("Checking for content_type column...")
        # 检查列是否存在
        result = await conn.execute(text(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_name='contents' AND column_name='content_type'"
        ))
        column_exists = result.fetchone() is not None
        
        if not column_exists:
            print("Adding content_type column to contents table...")
            await conn.execute(text("ALTER TABLE contents ADD COLUMN content_type VARCHAR(50)"))
            print("Column added successfully.")
        else:
            print("Column content_type already exists.")

if __name__ == "__main__":
    asyncio.run(migrate())
