"""回收不再被内容或资产引用的旧归档文件。"""
import asyncio
import json
import os
import re
import stat
import time
from pathlib import Path

from sqlalchemy import Text, cast, or_, select, update

from app.core.config import settings
from app.core.db_adapter import AsyncSessionLocal
from app.models import Content
from app.models.media import MediaVariant

_HASH = re.compile(r"\b[0-9a-f]{64}\b")
_DELETE_BATCH_SIZE = 16
_REFERENCE_COLUMNS = (
    Content.body, Content.cover_url, Content.author_avatar_url,
    Content.media_urls, Content.archive_metadata, Content.rich_payload,
)


async def _load_reference_values(db, digests: set[str] | None = None):
    contents = select(*_REFERENCE_COLUMNS)
    variants = select(MediaVariant.storage_key)
    if digests is not None:
        contents = contents.where(or_(*(
            cast(column, Text).contains(digest)
            for digest in digests for column in _REFERENCE_COLUMNS
        )))
        variants = variants.where(or_(*(
            MediaVariant.storage_key.contains(digest) for digest in digests
        )))
    rows = (await db.execute(contents)).all()
    keys = (await db.scalars(variants)).all()
    return rows, keys


def _reference_hashes(rows, keys) -> set[str]:
    # Include legacy/local references and soft-deleted content, not only variants.
    referenced = set()
    for row in rows:
        referenced.update(_HASH.findall(json.dumps(list(row), ensure_ascii=False)))
    for key in keys:
        referenced.update(_HASH.findall(key or ""))
    return referenced


def _scan_candidates(root: Path, cutoff: float, rows, keys) -> list[tuple[Path, str]]:
    referenced = _reference_hashes(rows, keys)
    candidates = []
    # Namespaces may be nested. Once a blob tree is found, do not walk its hash
    # shards again looking for more blob trees.
    for directory, subdirectories, _ in os.walk(root, followlinks=False):
        folder = Path(directory)
        if folder.name != "sha256" or folder.parent.name != "blobs":
            continue
        subdirectories.clear()
        with os.scandir(folder) as first_level:
            for first in first_level:
                if not first.is_dir(follow_symlinks=False):
                    continue
                with os.scandir(first.path) as second_level:
                    for second in second_level:
                        if not second.is_dir(follow_symlinks=False):
                            continue
                        with os.scandir(second.path) as files:
                            for entry in files:
                                digest = entry.name.split(".", 1)[0]
                                if not _HASH.fullmatch(digest) or digest in referenced:
                                    continue
                                try:
                                    info = entry.stat(follow_symlinks=False)
                                except FileNotFoundError:
                                    continue
                                if stat.S_ISREG(info.st_mode) and info.st_mtime < cutoff:
                                    candidates.append((Path(entry.path), digest))
    return candidates


def _remove_candidates(candidates, referenced: set[str], cutoff: float) -> tuple[int, int]:
    count = size = 0
    for path, digest in candidates:
        if digest in referenced:
            continue
        try:
            # Recheck after the scan: a concurrent archive may have replaced it.
            info = path.lstat()
            if not stat.S_ISREG(info.st_mode) or info.st_mtime >= cutoff:
                continue
            if path.resolve() != path:
                continue
            path.unlink()
        except FileNotFoundError:
            continue
        count += 1
        size += info.st_size
    return count, size


async def cleanup_unreferenced_media() -> tuple[int, int]:
    root = Path(settings.storage_local_root).resolve()
    cutoff = time.time() - 86400  # Downloads may precede their DB transaction.
    async with AsyncSessionLocal() as db:
        rows, keys = await _load_reference_values(db)
    candidates = await asyncio.to_thread(_scan_candidates, root, cutoff, rows, keys)

    count = size = 0
    for offset in range(0, len(candidates), _DELETE_BATCH_SIZE):
        batch = candidates[offset:offset + _DELETE_BATCH_SIZE]
        async with AsyncSessionLocal() as db, db.begin():
            # Serialize the fresh reference check and deletion with reference
            # writers, without holding that lock during the directory scan.
            await db.execute(update(Content).where(Content.id == -1).values(id=-1))
            rows, keys = await _load_reference_values(db, {digest for _, digest in batch})
            referenced = _reference_hashes(rows, keys)
            # Keep this bounded unlink synchronous: a cancelled to_thread would
            # keep deleting after the surrounding DB transaction released its lock.
            removed, freed = _remove_candidates(batch, referenced, cutoff)
        count += removed
        size += freed
    return count, size
