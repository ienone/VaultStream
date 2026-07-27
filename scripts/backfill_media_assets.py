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


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Report or backfill the unified VaultStream media asset tables.",
    )
    parser.add_argument(
        "--db",
        type=Path,
        default=BACKEND_ROOT / "data" / "vaultstream.db",
        help="SQLite database path.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Persist candidates. Without this flag the command is read-only.",
    )
    return parser.parse_args()


async def _run() -> int:
    args = _parse_args()
    db_path = args.db.resolve()
    if not db_path.is_file():
        raise SystemExit(f"Database does not exist: {db_path}")
    os.environ["SQLITE_DB_PATH"] = str(db_path)
    os.environ.setdefault("STORAGE_LOCAL_ROOT", str(BACKEND_ROOT / "data" / "storage"))

    from app.adapters.storage import get_storage_backend
    from app.core.database import init_db
    from app.core.db_adapter import AsyncSessionLocal, engine
    from app.services.media_backfill import backfill_media_assets

    try:
        if args.apply:
            await init_db()
        async with AsyncSessionLocal() as session:
            report = await backfill_media_assets(
                session,
                get_storage_backend(),
                apply=args.apply,
            )
        print(json.dumps(report.to_dict(), ensure_ascii=False, indent=2))
        return 0
    finally:
        await engine.dispose()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_run()))
