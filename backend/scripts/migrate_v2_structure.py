import sys
import os
import json
import asyncio
import logging
from typing import Dict, Any, List

# Ensure backend path is in sys.path
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

from sqlalchemy import text
from app.core.db_adapter import AsyncSessionLocal
from app.models import Platform

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _is_column_already_exists_error(error: Exception) -> bool:
    message = str(error).lower()
    return "already exists" in message or "duplicate column" in message


async def _get_existing_columns(db) -> set[str]:
    """兼容 SQLite/PostgreSQL，返回 contents 表当前存在的列集合。"""
    try:
        result = await db.execute(text("PRAGMA table_info(contents)"))
        rows = result.fetchall()
        if rows:
            columns: set[str] = set()
            for row in rows:
                # PRAGMA table_info: [cid, name, type, notnull, dflt_value, pk]
                col_name = row[1] if len(row) > 1 else None
                if col_name:
                    columns.add(str(col_name))
            if columns:
                return columns
    except Exception:
        pass

    result = await db.execute(text(
        "SELECT column_name FROM information_schema.columns WHERE table_name = 'contents'"
    ))
    return {str(row[0]) for row in result.fetchall() if row and row[0]}

async def migrate():
    async with AsyncSessionLocal() as db:
        logger.info("Starting migration to V2 structure (Field Replacement)...")
        
        # 1. Add columns if not exist
        columns_to_add = [
            ("context_data", "JSON"),
            ("rich_payload", "JSON"),
            ("archive_metadata", "JSON"),
            ("deleted_at", "DATETIME")
        ]
        
        for col_name, col_type in columns_to_add:
            try:
                await db.execute(text(f"ALTER TABLE contents ADD COLUMN {col_name} {col_type}"))
                logger.info(f"Added column: {col_name}")
            except Exception as e:
                # 只忽略预期的“列已存在”情况，其余错误直接抛出。
                if _is_column_already_exists_error(e):
                    logger.info(f"Column already exists, skipping: {col_name}")
                else:
                    logger.error(f"Failed to add column {col_name}: {e}")
                    raise

        await db.commit()

        existing_columns = await _get_existing_columns(db)
        logger.info(f"Detected columns: {sorted(existing_columns)}")
        
        # 2. Iterate and Migrate Data using Raw SQL
        # We use raw SQL because the ORM model might have these fields removed.
        select_columns = ["id", "platform", "context_data", "rich_payload", "archive_metadata"]
        for legacy_col in ("raw_metadata", "associated_question", "top_answers"):
            if legacy_col in existing_columns:
                select_columns.append(legacy_col)
        stmt = text(f"SELECT {', '.join(select_columns)} FROM contents")
        result = await db.execute(stmt)
        rows = result.mappings().all()
        
        migrated_count = 0
        
        for row in rows:
            content_id = row['id']
            platform = row['platform']
            
            # JSON parsing (SQLite returns strings for JSON sometimes, or already parsed depending on driver)
            # SQLAlchemy mappings usually handle this if types are defined, but here we are raw.
            # aiosqlite usually returns parsed json if column type is JSON? No, it returns string.
            # Let's handle both.
            
            def parse_json(val, field_name: str):
                if not val: return None
                if isinstance(val, dict) or isinstance(val, list): return val
                try:
                    return json.loads(val)
                except Exception as e:
                    logger.warning(
                        "Failed to parse json for content_id=%s field=%s: %s",
                        content_id,
                        field_name,
                        e,
                    )
                    return None

            raw_metadata = parse_json(row.get('raw_metadata'), 'raw_metadata')
            associated_question = parse_json(row.get('associated_question'), 'associated_question')
            top_answers = parse_json(row.get('top_answers'), 'top_answers')
            
            # Check if already migrated
            if row['archive_metadata'] or row['context_data'] or row['rich_payload']:
                # Already populated? maybe partial.
                # We overwrite if new fields are empty.
                pass

            updates = {}
            
            # 2.1 Migrate raw_metadata -> archive_metadata
            if raw_metadata and not row['archive_metadata']:
                updates["archive_metadata"] = raw_metadata
                # We logically "remove" raw_metadata by ignoring it in future, 
                # effectively setting it to NULL in DB is good practice to avoid confusion.
                if "raw_metadata" in existing_columns:
                    updates["raw_metadata"] = None
            
            # 2.2 Migrate Zhihu associated_question -> context_data
            if platform == 'zhihu': # platform is stored as string in DB usually 'zhihu'
                if associated_question and not row['context_data']:
                    aq = associated_question
                    context = {
                        "type": "question",
                        "title": aq.get("title"),
                        "url": aq.get("url") or f"https://www.zhihu.com/question/{aq.get('id')}",
                        "id": str(aq.get("id")) if aq.get("id") else None,
                        "stats": {
                            "answer_count": aq.get("answer_count"),
                            "follower_count": aq.get("follower_count"),
                            "visit_count": aq.get("visit_count")
                        }
                    }
                    if aq.get("cover_url"):
                        context["cover_url"] = aq.get("cover_url")
                        
                    updates["context_data"] = context
                    if "associated_question" in existing_columns:
                        updates["associated_question"] = None
                
                # 2.3 Migrate Zhihu top_answers -> rich_payload
                if top_answers and not row['rich_payload']:
                    answers = top_answers
                    blocks = []
                    for ans in answers:
                        # Handle potential string/dict difference
                        if isinstance(ans, str):
                            try:
                                ans = json.loads(ans)
                            except Exception as e:
                                logger.warning(
                                    "Failed to parse top_answers item for content_id=%s: %s",
                                    content_id,
                                    e,
                                )
                                continue
                        if not isinstance(ans, dict):
                            continue
                        
                        block_data = {
                            "type": "sub_item",
                            "data": {
                                "title": ans.get("author", {}).get("name"), 
                                "author_name": ans.get("author", {}).get("name"),
                                "excerpt": ans.get("excerpt"),
                                "voteup_count": ans.get("voteup_count"),
                                "url": ans.get("url"),
                                "cover_url": ans.get("thumbnail") or ans.get("cover_url")
                            }
                        }
                        blocks.append(block_data)
                    
                    if blocks:
                        updates["rich_payload"] = {"blocks": blocks}
                        if "top_answers" in existing_columns:
                            updates["top_answers"] = None
            
            if updates:
                # Construct update query
                set_clauses = []
                params = {"id": content_id}
                for k, v in updates.items():
                    set_clauses.append(f"{k} = :{k}")
                    # Serialize dicts/lists to JSON string for SQLite if necessary
                    # SQLAlchemy `text` with params handles simple types, but for JSON column we might need json.dumps
                    # if the driver doesn't do it automatically. 
                    # With asyncpg/aiosqlite + SQLAlchemy, passing dict usually works if bindparam type is JSON.
                    # But here we are using raw text. Safest is json.dumps.
                    if isinstance(v, (dict, list)):
                        params[k] = json.dumps(v, ensure_ascii=False)
                    else:
                        params[k] = v
                
                query = text(f"UPDATE contents SET {', '.join(set_clauses)} WHERE id = :id")
                await db.execute(query, params)
                migrated_count += 1
                
        if migrated_count > 0:
            await db.commit()
            logger.info(f"Successfully migrated {migrated_count} content items.")
        else:
            logger.info("No content items needed migration.")

        # 3. Final cleanup: clear legacy columns for all rows to avoid mixed-era ambiguity.
        cleanup_updates = 0
        for legacy_col in ("raw_metadata", "associated_question", "top_answers"):
            if legacy_col in existing_columns:
                await db.execute(text(f"UPDATE contents SET {legacy_col} = NULL WHERE {legacy_col} IS NOT NULL"))
                cleanup_updates += 1
        if cleanup_updates:
            await db.commit()
            logger.info("Legacy columns cleanup completed for all rows.")

if __name__ == "__main__":
    asyncio.run(migrate())
