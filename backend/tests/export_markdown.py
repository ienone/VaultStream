#!/usr/bin/env python3

"""Export one archived content to Markdown.

This reads Content.archive_metadata.archive and emits a Markdown file.

Features:
- Optionally re-run private archive image processing (download -> WebP -> store to MinIO/S3/LocalFS)
- Replace image links in archive['markdown'] with stored URLs when available

Usage examples:
  ./venv/bin/python tests/export_markdown.py --content-id 7 --out exports/content_7.md
  ./venv/bin/python tests/export_markdown.py --content-id 6 --out exports/content_6.md --process-missing-images --max-images 10

Notes:
- Export does NOT require STORAGE_PUBLIC_BASE_URL.
  - Without it, the output Markdown will usually keep original remote image URLs.
  - To rewrite images to MinIO/S3 URLs, configure STORAGE_PUBLIC_BASE_URL so the system can map stored_key -> URL.
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from typing import Any, Optional

from sqlalchemy import select


# Make `import app.*` work when running this file from `tests/`.
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)


from app.config import settings  # noqa: E402
from app.database import AsyncSessionLocal  # noqa: E402
from app.models import Content  # noqa: E402
from app.storage import get_storage_backend  # noqa: E402
from app.media_processing import store_archive_images_as_webp  # noqa: E402


def _ensure_parent_dir(path: str) -> None:
    parent = os.path.dirname(os.path.abspath(path))
    if parent:
        os.makedirs(parent, exist_ok=True)


def _coalesce(*vals: Optional[str]) -> Optional[str]:
    for v in vals:
        if isinstance(v, str) and v.strip():
            return v.strip()
    return None


def _replace_urls_in_markdown(markdown: str, replacements: dict[str, str]) -> str:
    out = markdown
    for src, dst in replacements.items():
        if not src or not dst:
            continue
        # Conservative replace; archive markdown typically uses the raw URL in link target.
        out = out.replace(src, dst)
    return out


async def _load_content(content_id: int) -> Content:
    async with AsyncSessionLocal() as session:
        result = await session.execute(select(Content).where(Content.id == content_id))
        content = result.scalar_one_or_none()
        if not content:
            raise SystemExit(f"Content not found: id={content_id}")
        # Detach by returning the ORM object; we will re-open a session if we need to persist changes.
        return content


async def _persist_archive_metadata(content_id: int, archive_metadata: dict[str, Any]) -> None:
    async with AsyncSessionLocal() as session:
        result = await session.execute(select(Content).where(Content.id == content_id))
        content = result.scalar_one()
        content.archive_metadata = archive_metadata
        await session.commit()


async def _maybe_process_images(
    *,
    content_id: int,
    archive_metadata: dict[str, Any],
    quality: int,
    max_images: Optional[int],
) -> dict[str, Any]:
    archive = archive_metadata.get("archive")
    if not isinstance(archive, dict):
        return archive_metadata

    images = archive.get("images")
    if not isinstance(images, list) or not images:
        return archive_metadata

    storage = get_storage_backend()
    ensure_bucket = getattr(storage, "ensure_bucket", None)
    if callable(ensure_bucket):
        await ensure_bucket()

    await store_archive_images_as_webp(
        archive=archive,
        storage=storage,
        namespace="vaultstream",
        quality=quality,
        max_images=max_images,
    )

    await _persist_archive_metadata(content_id, archive_metadata)
    return archive_metadata


async def _export(
    *,
    content_id: int,
    out_path: str,
    process_missing_images: bool,
    quality: int,
    max_images: Optional[int],
) -> None:
    content = await _load_content(content_id)
    raw = content.archive_metadata
    if not isinstance(raw, dict):
        raise SystemExit("archive_metadata is empty or invalid; nothing to export")

    if process_missing_images:
        raw = await _maybe_process_images(
            content_id=content_id,
            archive_metadata=raw,
            quality=quality,
            max_images=max_images,
        )

    archive = raw.get("archive")
    if not isinstance(archive, dict):
        raise SystemExit("archive_metadata.archive not found; this content may not support archive export")

    title = _coalesce(archive.get("title"), content.title) or f"Content {content_id}"
    md = archive.get("markdown")

    # Build replacement map from original URL -> stored URL
    replacements: dict[str, str] = {}
    images = archive.get("images")
    if isinstance(images, list):
        storage = get_storage_backend()
        for img in images:
            if not isinstance(img, dict):
                continue
            orig_url = img.get("url")
            stored_url = img.get("stored_url")
            stored_key = img.get("stored_key")
            if isinstance(orig_url, str) and orig_url.strip():
                if isinstance(stored_url, str) and stored_url.strip():
                    replacements[orig_url.strip()] = stored_url.strip()
                elif isinstance(stored_key, str) and stored_key.strip():
                    # If STORAGE_PUBLIC_BASE_URL is configured, storage.get_url() will return a URL.
                    url = storage.get_url(key=stored_key.strip())
                    if isinstance(url, str) and url.strip():
                        replacements[orig_url.strip()] = url.strip()

    if isinstance(md, str) and md.strip():
        body = _replace_urls_in_markdown(md, replacements)
        out_md = body
    else:
        # Fallback: simple Markdown if archive markdown is missing.
        lines = [f"# {title}", ""]
        desc = (content.description or "").strip()
        if desc:
            lines += [desc, ""]
        if isinstance(images, list) and images:
            lines += ["## Images", ""]
            for img in images:
                if not isinstance(img, dict):
                    continue
                orig_url = img.get("url")
                stored_url = img.get("stored_url")
                stored_key = img.get("stored_key")
                chosen = None
                if isinstance(stored_url, str) and stored_url.strip():
                    chosen = stored_url.strip()
                elif isinstance(stored_key, str) and stored_key.strip():
                    chosen = get_storage_backend().get_url(key=stored_key.strip())
                elif isinstance(orig_url, str) and orig_url.strip():
                    chosen = orig_url.strip()
                if chosen:
                    lines.append(f"![]({chosen})")
            lines.append("")
        out_md = "\n".join(lines)

    _ensure_parent_dir(out_path)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(out_md)

    print(f"Exported: {out_path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--content-id", type=int, required=True)
    parser.add_argument("--out", type=str, required=True)
    parser.add_argument(
        "--process-missing-images",
        action="store_true",
        help="Re-run image processing and persist stored_* fields",
    )
    parser.add_argument(
        "--quality",
        type=int,
        default=int(getattr(settings, "archive_image_webp_quality", 80) or 80),
    )
    parser.add_argument("--max-images", type=int, default=None)
    args = parser.parse_args()

    asyncio.run(
        _export(
            content_id=args.content_id,
            out_path=args.out,
            process_missing_images=bool(args.process_missing_images),
            quality=int(args.quality),
            max_images=args.max_images,
        )
    )


if __name__ == "__main__":
    main()
