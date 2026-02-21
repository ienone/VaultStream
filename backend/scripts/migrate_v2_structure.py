import sys
import os
import json
import asyncio
import logging
from typing import Dict, Any, List

# Ensure backend path is in sys.path
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

from sqlalchemy import text, select, update
from app.core.db_adapter import AsyncSessionLocal
from app.models import Content, Platform

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

async def migrate():
    async with AsyncSessionLocal() as db:
        logger.info("Starting migration to V2 structure...")
        
        # 1. Add columns if not exist
        # SQLite adds columns one by one.
        # Check if columns exist first.
        # We can use a simple try-except block or inspect.
        # For simplicity, we'll try to add them and ignore errors.
        
        columns_to_add = [
            ("context_data", "JSON"),
            ("rich_payload", "JSON"),
            ("archive_metadata", "JSON"),
            ("deleted_at", "DATETIME")
        ]
        
        for col_name, col_type in columns_to_add:
            try:
                # SQLite syntax
                await db.execute(text(f"ALTER TABLE contents ADD COLUMN {col_name} {col_type}"))
                logger.info(f"Added column: {col_name}")
            except Exception as e:
                # Likely already exists
                logger.info(f"Column {col_name} might already exist or error: {e}")

        await db.commit()
        
        # 2. Iterate and Migrate Data
        # Fetch all contents
        stmt = select(Content)
        result = await db.execute(stmt)
        contents = result.scalars().all()
        
        migrated_count = 0
        
        for content in contents:
            needs_update = False
            
            # 2.1 Migrate raw_metadata -> archive_metadata
            if content.raw_metadata and not content.archive_metadata:
                content.archive_metadata = content.raw_metadata
                # content.raw_metadata = None # We will clear later or now? 
                # Better clear it now to free space, but for safety, maybe keep it?
                # The plan implies moving it. "归档: 将 raw_metadata 移动到 archive_metadata"
                content.raw_metadata = None 
                needs_update = True
            
            # 2.2 Migrate Zhihu associated_question -> context_data
            # Old Structure: associated_question (JSON)
            # New Structure: context_data = {"type": "question", "title": ..., "url": ...}
            if content.platform == Platform.ZHIHU:
                if content.associated_question and not content.context_data:
                    aq = content.associated_question
                    # Assuming aq has title, url, etc.
                    # Adapt based on actual structure.
                    # Usually associated_question has {title, url, type, created, updated, etc.}
                    # We map it to context_data.
                    context = {
                        "type": "question",
                        "title": aq.get("title"),
                        "url": aq.get("url") or f"https://www.zhihu.com/question/{aq.get('id')}",
                        "id": str(aq.get("id")) if aq.get("id") else None
                    }
                    if aq.get("cover_url"):
                        context["cover_url"] = aq.get("cover_url")
                        
                    content.context_data = context
                    content.associated_question = None # Clear old
                    needs_update = True
                
                # 2.3 Migrate Zhihu top_answers -> rich_payload
                # Old Structure: top_answers (List[Dict])
                # New Structure: rich_payload = {"blocks": [{"type": "sub_item", "data": ...}]}
                if content.top_answers and not content.rich_payload:
                    answers = content.top_answers
                    blocks = []
                    for ans in answers:
                        block_data = {
                            "type": "sub_item", # or "answer"
                            "data": {
                                "title": ans.get("author", {}).get("name"), # Answer author as title or subtitle?
                                # Usually sub items in a list.
                                "author_name": ans.get("author", {}).get("name"),
                                "excerpt": ans.get("excerpt"),
                                "voteup_count": ans.get("voteup_count"),
                                "url": ans.get("url"),
                                "cover_url": ans.get("thumbnail") or ans.get("cover_url")
                            }
                        }
                        blocks.append(block_data)
                    
                    if blocks:
                        content.rich_payload = {"blocks": blocks}
                        content.top_answers = None # Clear old
                        needs_update = True
            
            if needs_update:
                migrated_count += 1
                
        if migrated_count > 0:
            await db.commit()
            logger.info(f"Successfully migrated {migrated_count} content items.")
        else:
            logger.info("No content items needed migration.")

if __name__ == "__main__":
    asyncio.run(migrate())
