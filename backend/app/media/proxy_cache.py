import asyncio
import hashlib
import os
from pathlib import Path

from app.adapters.storage import LocalStorageBackend


def proxy_cache_location(url: str) -> tuple[str, str]:
    digest = hashlib.md5(url.encode(), usedforsecurity=False).hexdigest()
    return f"proxy_cache/{digest[:2]}/{digest[2:4]}", digest


def _proxy_cache_media_type(path: str) -> str | None:
    """Infer the media type encoded by a cache filename, never assume WebP."""
    # Use exactly the formats we write; minimal container MIME tables omit WebP.
    return {
        ".webp": "image/webp", ".jpg": "image/jpeg", ".png": "image/png",
        ".gif": "image/gif", ".avif": "image/avif", ".bmp": "image/bmp",
        ".tif": "image/tiff",
    }.get(Path(path).suffix.lower())


async def find_proxy_cache_file(
    storage: LocalStorageBackend,
    cache_namespace: str,
    url_hash: str,
) -> tuple[str, str] | None:
    """Find a readable cached image without blocking the event loop."""
    cache_dir = storage._full_path(cache_namespace)

    def find_file() -> tuple[str, str] | None:
        if not os.path.exists(cache_dir):
            return None
        for filename in sorted(os.listdir(cache_dir)):
            if Path(filename).stem != url_hash:
                continue
            cached_file = os.path.join(cache_dir, filename)
            media_type = _proxy_cache_media_type(cached_file)
            if media_type and os.path.isfile(cached_file):
                return cached_file, media_type
        return None

    return await asyncio.to_thread(find_file)
