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
    parser.add_argument("--repair-media", action="store_true",
                        help="Queue missing-media repair for existing assets, respecting archive settings.")
    parser.add_argument("--storage-root", type=Path,
                        help="Existing media storage directory (defaults to the database directory/storage).")
    return parser.parse_args()


async def _run() -> int:
    args = _parse_args()
    db_path = args.db.resolve()
    if not db_path.is_file():
        raise SystemExit(f"Database does not exist: {db_path}")
    os.environ["SQLITE_DB_PATH"] = str(db_path)
    os.environ["STORAGE_LOCAL_ROOT"] = str((args.storage_root or db_path.parent / "storage").resolve())

    from app.adapters.storage import get_storage_backend
    from app.core.database import init_db
    from app.core.db_adapter import AsyncSessionLocal, engine
    from app.services.media_backfill import backfill_media_assets

    try:
        if args.apply:
            await init_db()
        async with AsyncSessionLocal() as session:
            if args.repair_media:
                from sqlalchemy import select
                from app.models import Content
                from app.models.media import MediaAsset, MediaType
                from app.services.media_repair import enqueue_media_repair
                ids = list((await session.scalars(select(Content.id).join(MediaAsset).where(
                    Content.deleted_at.is_(None), MediaAsset.original_url.is_not(None),
                    MediaAsset.media_type.in_([MediaType.IMAGE, MediaType.VIDEO]),
                ).distinct())).all())
                queued = 0
                if args.apply:
                    for content_id in ids:
                        queued += await enqueue_media_repair(session, content_id)
                        await session.commit()
                print(json.dumps({"mode": "apply" if args.apply else "dry_run",
                                  "candidate_contents": len(ids), "queued_or_pending": queued,
                                  "execution": "existing task worker; archive settings apply"}))
                return 0
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
