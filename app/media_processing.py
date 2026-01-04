"""媒体处理工具

当前范围：
- 下载私有存档引用的远程图片，通过存储后端转换为WebP格式存储
- 就地更新存档中的存储资产引用

未来范围：
- 视频/音频下载、转码和衍生变体（HLS、缩略图、波形图）
"""

from __future__ import annotations

import asyncio
import hashlib
from dataclasses import dataclass
from typing import Any, Optional

import httpx

from app.logging import logger
from app.storage import StorageBackend


def _request_headers_for_url(url: str) -> dict[str, str]:
    """根据URL生成请求头（某些CDN如B站需要浏览器样式的请求头）"""
    headers: dict[str, str] = {
        "User-Agent": (
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        ),
        "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
    }

    lowered = (url or "").lower()
    if "hdslb.com/" in lowered:
        headers["Referer"] = "https://www.bilibili.com/"
        headers["Origin"] = "https://www.bilibili.com"

    return headers


@dataclass(frozen=True)
class StoredImageInfo:
    """存储的图片信息"""
    orig_url: str
    key: str
    url: Optional[str]
    sha256: str
    size: int
    width: Optional[int] = None
    height: Optional[int] = None
    content_type: str = "image/webp"


def _sha256_bytes(data: bytes) -> str:
    """计算字节数据的SHA256哈希值"""
    return hashlib.sha256(data).hexdigest()


def _content_addressed_key(namespace: str, sha256_hex: str, ext: str) -> str:
    """生成基于内容寻址的存储key"""
    ns = (namespace or "").strip("/")
    prefix = f"{ns}/" if ns else ""
    return f"{prefix}blobs/sha256/{sha256_hex[:2]}/{sha256_hex[2:4]}/{sha256_hex}.{ext.lstrip('.')}"


def _image_to_webp(data: bytes, quality: int = 80) -> tuple[bytes, Optional[int], Optional[int]]:
    """将图片转换为WebP格式"""
    try:
        from PIL import Image  # type: ignore
    except Exception as e:  # pragma: no cover
        raise RuntimeError("WebP转码需要安装 Pillow") from e

    from io import BytesIO

    with Image.open(BytesIO(data)) as im:
        width, height = im.size
        if im.mode in ("P", "LA"):
            im = im.convert("RGBA")
        elif im.mode not in ("RGB", "RGBA"):
            im = im.convert("RGB")

        out = BytesIO()
        im.save(out, format="WEBP", quality=int(quality), method=6)
        return out.getvalue(), int(width) if width else None, int(height) if height else None


async def store_archive_images_as_webp(
    *,
    archive: dict[str, Any],
    storage: StorageBackend,
    namespace: str,
    quality: int = 80,
    timeout_seconds: float = 30.0,
    max_images: Optional[int] = None,
) -> dict[str, Any]:
    """下载并存储存档中的图片为WebP格式，更新存档引用。

    期望存档结构类似于 bilibili_opus 存档 v2：
    - archive['images'] 是包含至少 {'url': 'https://...'} 的字典列表

    更新内容：
    - 添加 archive['stored_images'] 列表，包含存储的引用
    - 对于 archive['images'] 中的每个条目，添加可选的 'stored_key'/'stored_url'/'stored_sha256'
    - 如果存储后端提供 URL，替换 archive['markdown'] 中的图片链接

    Returns:
        更新后的存档字典（同一对象被修改）。
    """

    images = archive.get("images")
    if not isinstance(images, list) or not images:
        return archive

    stored_images: list[dict[str, Any]] = []
    url_to_stored_url: dict[str, str] = {}

    count = 0
    async with httpx.AsyncClient(timeout=timeout_seconds, follow_redirects=True) as client:
        for img in images:
            if max_images is not None and count >= max_images:
                break
            if not isinstance(img, dict):
                continue
            orig_url = img.get("url")
            if not isinstance(orig_url, str) or not orig_url.strip():
                continue
            orig_url = orig_url.strip()

            # Skip if already processed
            if isinstance(img.get("stored_key"), str) and img.get("stored_key"):
                continue

            webp_bytes = None
            width = None
            height = None
            key = None
            sha256_hex = None

            # Best-effort retries for transient failures (network hiccups, CDN throttling).
            for attempt in range(3):
                try:
                    resp = await client.get(orig_url, headers=_request_headers_for_url(orig_url))
                    resp.raise_for_status()
                    src_bytes = resp.content
                    webp_bytes, width, height = _image_to_webp(src_bytes, quality=quality)
                    sha256_hex = _sha256_bytes(webp_bytes)
                    key = _content_addressed_key(namespace, sha256_hex, "webp")
                    await storage.put_bytes(key=key, data=webp_bytes, content_type="image/webp")
                    break
                except Exception as e:
                    is_last = attempt >= 2
                    if is_last:
                        logger.warning(
                            "Process image failed: {} (attempt={}/3, {})",
                            orig_url,
                            attempt + 1,
                            f"{type(e).__name__}: {e}",
                        )
                    else:
                        await asyncio.sleep(0.8 * (attempt + 1))
                        continue

            if not (webp_bytes and key and sha256_hex):
                continue

            stored_url = storage.get_url(key=key)
            info = StoredImageInfo(
                orig_url=orig_url,
                key=key,
                url=stored_url,
                sha256=sha256_hex,
                size=len(webp_bytes),
                width=width,
                height=height,
            )

            img["stored_key"] = info.key
            img["stored_url"] = info.url
            img["stored_sha256"] = info.sha256
            img["stored_size"] = info.size
            img["stored_width"] = info.width
            img["stored_height"] = info.height
            img["stored_content_type"] = info.content_type

            stored_images.append(
                {
                    "orig_url": info.orig_url,
                    "key": info.key,
                    "url": info.url,
                    "sha256": info.sha256,
                    "size": info.size,
                    "width": info.width,
                    "height": info.height,
                    "content_type": info.content_type,
                }
            )

            if info.url:
                url_to_stored_url[orig_url] = info.url

            count += 1

    if stored_images:
        archive["stored_images"] = stored_images

    md = archive.get("markdown")
    if isinstance(md, str) and md and url_to_stored_url:
        for src_url, dst_url in url_to_stored_url.items():
            archive["markdown"] = archive["markdown"].replace(f"]({src_url})", f"]({dst_url})")

    logger.info(
        "Archive images processed: total_images={}, stored_images={}",
        len(images),
        len(stored_images),
    )

    return archive
