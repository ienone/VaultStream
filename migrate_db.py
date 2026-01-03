import asyncio
from sqlalchemy import text

from app.database import engine


async def _column_exists(conn, table: str, column: str) -> bool:
    result = await conn.execute(
        text(
            "SELECT 1 FROM information_schema.columns "
            "WHERE table_name=:t AND column_name=:c"
        ),
        {"t": table, "c": column},
    )
    return result.fetchone() is not None


async def _table_exists(conn, table: str) -> bool:
    result = await conn.execute(
        text("SELECT 1 FROM information_schema.tables WHERE table_name=:t"),
        {"t": table},
    )
    return result.fetchone() is not None


async def _constraint_exists(conn, table: str, constraint: str) -> bool:
    result = await conn.execute(
        text(
            "SELECT 1 FROM information_schema.table_constraints "
            "WHERE table_name=:t AND constraint_name=:c"
        ),
        {"t": table, "c": constraint},
    )
    return result.fetchone() is not None


async def migrate():
    async with engine.begin() as conn:
        # 兼容旧版：content_type
        if not await _column_exists(conn, "contents", "content_type"):
            print("Adding content_type column to contents table...")
            await conn.execute(text("ALTER TABLE contents ADD COLUMN content_type VARCHAR(50)"))

        # M1: canonical_url
        if not await _column_exists(conn, "contents", "canonical_url"):
            print("Adding canonical_url column to contents table...")
            await conn.execute(text("ALTER TABLE contents ADD COLUMN canonical_url TEXT"))

        # backfill canonical_url for existing rows
        await conn.execute(
            text(
                "UPDATE contents "
                "SET canonical_url = COALESCE(canonical_url, clean_url, url) "
                "WHERE canonical_url IS NULL"
            )
        )

        # M1.1: failure record columns (minimal rollback / manual fix basis)
        if not await _column_exists(conn, "contents", "failure_count"):
            print("Adding failure_count column to contents table...")
            await conn.execute(text("ALTER TABLE contents ADD COLUMN failure_count INTEGER NOT NULL DEFAULT 0"))

        if not await _column_exists(conn, "contents", "last_error"):
            print("Adding last_error column to contents table...")
            await conn.execute(text("ALTER TABLE contents ADD COLUMN last_error TEXT"))

        if not await _column_exists(conn, "contents", "last_error_type"):
            print("Adding last_error_type column to contents table...")
            await conn.execute(text("ALTER TABLE contents ADD COLUMN last_error_type VARCHAR(200)"))

        if not await _column_exists(conn, "contents", "last_error_detail"):
            print("Adding last_error_detail column to contents table...")
            await conn.execute(text("ALTER TABLE contents ADD COLUMN last_error_detail JSON"))

        if not await _column_exists(conn, "contents", "last_error_at"):
            print("Adding last_error_at column to contents table...")
            await conn.execute(text("ALTER TABLE contents ADD COLUMN last_error_at TIMESTAMP WITHOUT TIME ZONE"))

        # 语义调整：DISTRIBUTED 不作为存档状态（历史数据回写到 PULLED）
        # 注意：本库的 Postgres enum label 使用的是成员名（大写），不是 value（小写）。
        await conn.execute(
            text("UPDATE contents SET status='PULLED' WHERE status='DISTRIBUTED'")
        )

        # 这是
        uq_name = "uq_contents_platform_canonical_url"
        if not await _constraint_exists(conn, "contents", uq_name):
            print("Adding unique constraint on (platform, canonical_url)...")
            await conn.execute(
                text(
                    f"ALTER TABLE contents ADD CONSTRAINT {uq_name} UNIQUE (platform, canonical_url)"
                )
            )

        # M1: content_sources table
        if not await _table_exists(conn, "content_sources"):
            print("Creating content_sources table...")
            await conn.execute(
                text(
                    "CREATE TABLE content_sources ("
                    "id SERIAL PRIMARY KEY,"
                    "content_id INTEGER NOT NULL REFERENCES contents(id),"
                    "source VARCHAR(100),"
                    "tags_snapshot JSON DEFAULT '[]'::json,"
                    "note TEXT,"
                    "client_context JSON,"
                    "created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT (NOW() AT TIME ZONE 'UTC')"
                    ")"
                )
            )
            await conn.execute(text("CREATE INDEX ix_content_sources_content_id ON content_sources(content_id)"))
            await conn.execute(text("CREATE INDEX ix_content_sources_created_at ON content_sources(created_at)"))


if __name__ == "__main__":
    asyncio.run(migrate())
