"""回收不再被内容或资产引用的旧归档文件。"""
import asyncio
import json
import re
import time
from pathlib import Path

from sqlalchemy import select

from app.core.config import settings
from app.models import Content
from app.models.media import MediaVariant

_HASH = re.compile(r"\b[0-9a-f]{64}\b")


async def cleanup_unreferenced_media(db) -> tuple[int, int]:
    # Include legacy/local references and soft-deleted content, not only variants.
    referenced = set()
    rows = await db.execute(select(
        Content.body, Content.cover_url, Content.author_avatar_url,
        Content.media_urls, Content.archive_metadata, Content.rich_payload,
    ))
    for row in rows:
        referenced.update(_HASH.findall(json.dumps(list(row), ensure_ascii=False)))
    for key in await db.scalars(select(MediaVariant.storage_key)):
        referenced.update(_HASH.findall(key or ""))
    root = Path(settings.storage_local_root)
    cutoff = time.time() - 86400  # Downloads may be published before their DB transaction.

    def remove_old_unreferenced():
        count = size = 0
        if not root.exists():
            return count, size
        for folder in root.glob("**/blobs/sha256"):
            for path in folder.glob("*/*/*"):
                digest = path.name.split(".", 1)[0]
                if not _HASH.fullmatch(digest) or digest in referenced or path.is_symlink():
                    continue
                try:
                    stat = path.stat()
                    if stat.st_mtime >= cutoff or not path.is_file():
                        continue
                    path.unlink()
                except FileNotFoundError:
                    continue
                count += 1
                size += stat.st_size
        return count, size

    return await asyncio.to_thread(remove_old_unreferenced)
