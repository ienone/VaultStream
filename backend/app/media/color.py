"""封面颜色提取；归档时直接复用已解码的图片。"""
import asyncio
from io import BytesIO
from pathlib import Path
from urllib.parse import urlparse

import httpx
from PIL import Image, ImageOps

from app.adapters.storage import get_storage_backend
from app.core.logging import logger
from app.core.safe_fetch import safe_client_get
from app.services.config_service import ConfigService


def dominant_color(image: Image.Image) -> str:
    rgb = ImageOps.exif_transpose(image).convert("RGB")
    rgb.thumbnail((50, 50))
    red, green, blue = rgb.resize((1, 1), Image.Resampling.LANCZOS).getpixel((0, 0))
    return f"#{red:02x}{green:02x}{blue:02x}"


def _color_from_bytes(data: bytes) -> str:
    with Image.open(BytesIO(data)) as image:
        if not 0 < image.width * image.height <= 40_000_000:
            raise ValueError("Cover exceeds pixel limit")
        return dominant_color(image)


def _try_read_local_media(url: str) -> bytes | None:
    parsed = urlparse(url)
    if url.startswith("local://"):
        key = url.removeprefix("local://")
    elif not parsed.netloc and parsed.path.startswith("/media/"):
        key = parsed.path.removeprefix("/media/")
    else:
        return None
    storage = get_storage_backend()
    root = Path(storage.root_dir).resolve()
    path = Path(storage._full_path(key)).resolve()
    path.relative_to(root)
    return path.read_bytes()


async def extract_cover_color(url: str, timeout_seconds: float = 10.0) -> str | None:
    from app.media.processor import _build_request_url, _request_headers_for_url

    try:
        data = await asyncio.to_thread(_try_read_local_media, url)
        if data is None:
            proxy = await ConfigService().get_http_proxy()
            async with httpx.AsyncClient(proxy=proxy, timeout=timeout_seconds) as client:
                response = await safe_client_get(
                    client, _build_request_url(url), headers=_request_headers_for_url(url),
                    max_bytes=20 * 1024 * 1024, allowed_content_type_prefixes=("image/",),
                )
                if response.status_code >= 400:
                    return None
                data = response.content
        return await asyncio.to_thread(_color_from_bytes, data)
    except Exception as error:
        logger.warning("Cover color extraction failed: {}", type(error).__name__)
        return None
