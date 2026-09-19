from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND_ROOT = REPO_ROOT / "backend"
sys.path.insert(0, str(BACKEND_ROOT))


async def _run() -> int:
    parser = argparse.ArgumentParser(description="Validate VaultStream SQLite schema gates.")
    parser.add_argument(
        "--db",
        type=Path,
        default=os.environ.get("VAULTSTREAM_TEST_DB", str(BACKEND_ROOT / ".test-runtime" / "regression.db")),
        help="Test SQLite path to upgrade and validate; defaults to the reusable regression database.",
    )
    args = parser.parse_args()

    os.environ["SQLITE_DB_PATH"] = str(args.db.resolve())

    from app.core.database import init_db
    from app.core.db_adapter import engine
    from app.core.schema_gate import validate_database_schema

    try:
        await init_db()
        async with engine.connect() as conn:
            result = await validate_database_schema(conn)
        print(json.dumps(result, ensure_ascii=False, indent=2, default=str))
        return 0 if result["status"] == "ok" else 1
    finally:
        await engine.dispose()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_run()))
