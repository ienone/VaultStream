from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND_ROOT = REPO_ROOT / "backend"
sys.path.insert(0, str(BACKEND_ROOT))


async def _run() -> int:
    parser = argparse.ArgumentParser(description="Validate VaultStream SQLite schema gates.")
    parser.add_argument(
        "--db",
        type=Path,
        default=None,
        help="SQLite DB path to validate. Defaults to a temporary fresh DB.",
    )
    args = parser.parse_args()

    temp_dir: tempfile.TemporaryDirectory[str] | None = None
    if args.db is None:
        temp_dir = tempfile.TemporaryDirectory()
        db_path = Path(temp_dir.name) / "schema_gate.sqlite"
    else:
        db_path = args.db.resolve()
        db_path.parent.mkdir(parents=True, exist_ok=True)

    os.environ["SQLITE_DB_PATH"] = str(db_path)

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
        if temp_dir is not None:
            temp_dir.cleanup()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_run()))
