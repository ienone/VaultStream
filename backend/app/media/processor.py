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

from app.core.logging import logger
from app.core.storage import LocalStorageBackend


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
    elif "sinaimg.cn" in lowered or "weibocdn.com" in lowered:
        headers["Referer"] = "https://weibo.com/"
    elif "zhimg.com" in lowered or "zhihu.com" in lowered:
        headers["Referer"] = "https://www.zhihu.com/"
        headers["Origin"] = "https://www.zhihu.com"

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


def _image_to_webp_ffmpeg(data: bytes, quality: int = 80) -> Optional[tuple[bytes, int, int]]:
    """使用 ffmpeg 转码动画为 WebP（高性能）
    
    性能对比：
    - PNG 单帧：ffmpeg 1.4x 快，但输出大 3.8x（不推荐）
    - GIF 动画：ffmpeg 25x 快，输出大 3.9x（推荐）
    """
    import subprocess
    import tempfile
    import os
    from io import BytesIO
    
    try:
        with tempfile.NamedTemporaryFile(delete=False) as tmp_in:
            tmp_in.write(data)
            tmp_in_path = tmp_in.name
        
        with tempfile.NamedTemporaryFile(suffix=".webp", delete=False) as tmp_out:
            tmp_out_path = tmp_out.name
        
        try:
            # quality 映射：80 → crf 40（数值越低质量越好，范围0-63）
            crf = max(0, min(63, int(80 - quality / 100 * 30)))
            
            result = subprocess.run(
                [
                    "ffmpeg",
                    "-i", tmp_in_path,
                    "-c:v", "libwebp",
                    "-quality", str(100),  # 编码质量 0-100
                    "-crf", str(crf),      # 恒定质量模式
                    "-loop", "0",          # 无限循环
                    "-y",                  # 覆盖输出文件
                    tmp_out_path
                ],
                capture_output=True,
                timeout=120,
                check=False
            )
            
            if result.returncode != 0:
                logger.warning(f"ffmpeg 转码失败: {result.stderr.decode()}")
                return None
            
            with open(tmp_out_path, "rb") as f:
                webp_data = f.read()
            
            # 获取尺寸
            from PIL import Image
            with Image.open(BytesIO(webp_data)) as img:
                width, height = img.size
            
            return webp_data, width, height
        finally:
            os.unlink(tmp_in_path)
            os.unlink(tmp_out_path)
    
    except (FileNotFoundError, subprocess.TimeoutExpired, Exception) as e:
        logger.debug(f"ffmpeg 不可用或转码失败: {e}")
        return None


def _image_to_webp(data: bytes, quality: int = 80) -> tuple[bytes, Optional[int], Optional[int]]:
    """将图片转换为WebP格式，保留动画帧
    
    优先使用 ffmpeg（动画快 10+ 倍），降级到 Pillow
    """
    try:
        from PIL import Image  # type: ignore
    except Exception as e:  # pragma: no cover
        raise RuntimeError("WebP转码需要安装 Pillow") from e

    from io import BytesIO

    # 先尝试 ffmpeg（只对动画有效）
    with Image.open(BytesIO(data)) as im:
        is_animated = hasattr(im, 'n_frames') and im.n_frames > 1
    
    if is_animated:
        ffmpeg_result = _image_to_webp_ffmpeg(data, quality=quality)
        if ffmpeg_result:
            return ffmpeg_result[0], ffmpeg_result[1], ffmpeg_result[2]
        # ffmpeg 不可用，降级到 Pillow
        logger.info("ffmpeg 不可用，使用 Pillow 转码（速度较慢）")
    
    # Pillow 转码（用于单帧或 ffmpeg 不可用）
    with Image.open(BytesIO(data)) as im:
        width, height = im.size
        
        # 检查是否是动画图像（多帧）
        is_animated = hasattr(im, 'n_frames') and im.n_frames > 1
        
        if is_animated:
            # 提取所有帧和持续时间
            frames = []
            durations = []
            
            for frame_idx in range(im.n_frames):
                im.seek(frame_idx)
                
                # 转换颜色模式
                frame = im.convert("RGBA") if im.mode in ("P", "LA") else im.convert("RGB")
                frames.append(frame)
                
                # 获取帧延迟（毫秒）
                duration = im.info.get('duration', 100)
                durations.append(duration)
            
            # 保存为动态 WebP
            out = BytesIO()
            frames[0].save(
                out,
                format="WEBP",
                quality=int(quality),
                method=6,
                save_all=True,
                append_images=frames[1:],
                duration=durations,
                loop=0  # 无限循环
            )
            return out.getvalue(), int(width) if width else None, int(height) if height else None
        else:
            # 单帧图像，正常转换
            if im.mode in ("P", "LA"):
                im = im.convert("RGBA")
            elif im.mode not in ("RGB", "RGBA"):
                im = im.convert("RGB")

            out = BytesIO()
            im.save(out, format="WEBP", quality=int(quality), method=6)
            return out.getvalue(), int(width) if width else None, int(height) if height else None


def _create_thumbnail_webp(data: bytes, size: tuple[int, int] = (300, 300), quality: int = 70) -> bytes:
    """创建缩略图"""
    try:
        from PIL import Image
    except Exception as e:
        raise RuntimeError("缩略图生成需要安装 Pillow") from e

    from io import BytesIO
    with Image.open(BytesIO(data)) as im:
        # 保持比例缩放
        im.thumbnail(size, Image.Resampling.LANCZOS)
        out = BytesIO()
        im.save(out, format="WEBP", quality=quality)
        return out.getvalue()


def _get_dominant_color(data: bytes) -> Optional[str]:
    """获取图片的色彩主色调 (Hex 格式)"""
    try:
        from PIL import Image
    except ImportError:
        return None

    from io import BytesIO
    try:
        with Image.open(BytesIO(data)) as im:
            # 缩放到极小尺寸以快速获取主色
            im = im.convert("RGB")
            im.thumbnail((50, 50))
            
            # 使用简单的中位切分或缩放平均值
            # 这里采用缩放至 1x1 的平均值方法，简单且高效
            avg_color = im.resize((1, 1), Image.Resampling.LANCZOS).getpixel((0, 0))
            return '#{:02x}{:02x}{:02x}'.format(avg_color[0], avg_color[1], avg_color[2])
    except Exception as e:
        logger.warning(f"提取图片颜色失败: {e}")
        return None


async def extract_cover_color(url: str, timeout_seconds: float = 10.0) -> Optional[str]:
    """从 URL 提取封面主色调（无需启用完整的归档处理）"""
    if not url:
        return None
    
    from app.core.config import settings
    proxy = settings.http_proxy if hasattr(settings, 'http_proxy') and settings.http_proxy else None
    
    headers = _request_headers_for_url(url)
    try:
        async with httpx.AsyncClient(proxy=proxy, timeout=timeout_seconds, follow_redirects=True) as client:
            resp = await client.get(url, headers=headers)
            resp.raise_for_status()
            return _get_dominant_color(resp.content)
    except Exception as e:
        logger.warning(f"Failed to extract color from {url}: {e}")
        return None


async def store_archive_images_as_webp(
    *,
    archive: dict[str, Any],
    storage: LocalStorageBackend,
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
    
    # 配置代理（如 Twitter 图片需要代理）
    from app.core.config import settings
    proxy = settings.http_proxy if hasattr(settings, 'http_proxy') and settings.http_proxy else None
    
    async with httpx.AsyncClient(proxy=proxy, timeout=timeout_seconds, follow_redirects=True) as client:
        for img in images:
            if max_images is not None and count >= max_images:
                break
            if not isinstance(img, dict):
                continue
            orig_url = img.get("url")
            if not isinstance(orig_url, str) or not orig_url.strip():
                continue
            orig_url = orig_url.strip()
            
            # URL编码：处理中文字符和空格等特殊字符
            from urllib.parse import urlsplit, urlunsplit, quote
            parts = urlsplit(orig_url)
            # 只编码路径部分，保留已编码的字符
            encoded_path = quote(parts.path, safe='/%')
            encoded_query = quote(parts.query, safe='=&%')
            request_url = urlunsplit((parts.scheme, parts.netloc, encoded_path, encoded_query, parts.fragment))

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
                    resp = await client.get(request_url, headers=_request_headers_for_url(orig_url))
                    resp.raise_for_status()
                    src_bytes = resp.content
                    webp_bytes, width, height = _image_to_webp(src_bytes, quality=quality)
                    sha256_hex = _sha256_bytes(webp_bytes)
                    key = _content_addressed_key(namespace, sha256_hex, "webp")
                    await storage.put_bytes(key=key, data=webp_bytes, content_type="image/webp")
                    
                    # 同时生成并存储缩略图 (M3: 可视化列表加速)
                    try:
                        thumb_bytes = _create_thumbnail_webp(webp_bytes)
                        # thumb key 命名规范: hash.thumb.webp
                        thumb_key = key.replace(".webp", ".thumb.webp")
                        await storage.put_bytes(key=thumb_key, data=thumb_bytes, content_type="image/webp")
                        img["thumb_key"] = thumb_key
                        img["thumb_url"] = storage.get_url(key=thumb_key)
                    except Exception as thumb_err:
                        logger.warning(f"生成缩略图失败: {thumb_err}")
                    
                    # M5: 提取主图颜色
                    if count == 0:
                        try:
                            archive["dominant_color"] = _get_dominant_color(webp_bytes or src_bytes)
                        except Exception as color_err:
                            logger.warning(f"提取主色调失败: {color_err}")
                        
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

            # 构建存储条目，透传原始字典中的元数据 (如 type: "avatar")
            stored_item = {
                "orig_url": info.orig_url,
                "key": info.key,
                "url": info.url,
                "sha256": info.sha256,
                "size": info.size,
                "width": info.width,
                "height": info.height,
                "content_type": info.content_type,
            }
            # 将原始字典中除 url 以外的所有自定义键值对也存入 stored_images
            for k, v in img.items():
                if k not in stored_item and not k.startswith("stored_"):
                    stored_item[k] = v

            stored_images.append(stored_item)

            if info.url:
                url_to_stored_url[orig_url] = info.url
            if info.key:
                 # 优先使用 local:// 协议，以便后端 API 统一替换为代理 URL
                 url_to_stored_url[orig_url] = f"local://{info.key}"

            count += 1

    if stored_images:
        archive["stored_images"] = stored_images

    # 注意：不修改 archive["markdown"] 中的 URL
    # 前端通过 stored_images 的 orig_url -> key 映射来查找本地图片
    # 这样保持与知乎等其他解析器一致的结构

    logger.info(
        "Archive images processed: total_images={}, stored_images={}",
        len(images),
        len(stored_images),
    )

    return archive


async def store_archive_videos(
    *,
    archive: dict[str, Any],
    storage: LocalStorageBackend,
    namespace: str,
    timeout_seconds: float = 120.0,
    max_videos: Optional[int] = None,
) -> dict[str, Any]:
    """下载并存储存档中的视频，更新存档引用。

    期望存档结构（与图片类似）：
    - archive['videos'] 是包含至少 {'url': 'https://...'} 的字典列表

    更新内容：
    - 添加 archive['stored_videos'] 列表，包含存储的引用
    - 对于 archive['videos'] 中的每个条目，添加可选的 'stored_key'/'stored_url'/'stored_sha256'

    Args:
        archive: 存档字典
        storage: 存储后端
        namespace: 存储命名空间
        timeout_seconds: 下载超时时间
        max_videos: 最大处理视频数量

    Returns:
        更新后的存档字典（同一对象被修改）。
    """

    videos = archive.get("videos")
    if not isinstance(videos, list) or not videos:
        return archive

    stored_videos: list[dict[str, Any]] = []

    count = 0
    
    # 配置代理（如 Twitter 视频需要代理）
    from app.core.config import settings
    proxy = settings.http_proxy if hasattr(settings, 'http_proxy') and settings.http_proxy else None
    
    async with httpx.AsyncClient(proxy=proxy, timeout=timeout_seconds, follow_redirects=True) as client:
        for vid in videos:
            if max_videos is not None and count >= max_videos:
                break
            if not isinstance(vid, dict):
                continue
            orig_url = vid.get("url")
            if not isinstance(orig_url, str) or not orig_url.strip():
                continue
            orig_url = orig_url.strip()

            # Skip if already processed
            if isinstance(vid.get("stored_key"), str) and vid.get("stored_key"):
                continue

            video_bytes = None
            key = None
            sha256_hex = None

            # Best-effort retries for transient failures
            for attempt in range(3):
                try:
                    resp = await client.get(orig_url, headers=_request_headers_for_url(orig_url))
                    resp.raise_for_status()
                    video_bytes = resp.content
                    sha256_hex = _sha256_bytes(video_bytes)
                    
                    # 检测视频格式（从URL或内容类型）
                    content_type = resp.headers.get("content-type", "video/mp4")
                    if "video" not in content_type:
                        content_type = "video/mp4"  # 默认为 mp4
                    
                    # 从 content-type 提取扩展名
                    ext = "mp4"  # 默认
                    if "/" in content_type:
                        mime_subtype = content_type.split("/")[1].split(";")[0].strip()
                        if mime_subtype in ["mp4", "webm", "ogg", "mov", "avi", "mkv"]:
                            ext = mime_subtype
                    
                    key = _content_addressed_key(namespace, sha256_hex, ext)
                    await storage.put_bytes(key=key, data=video_bytes, content_type=content_type)
                    break
                except Exception as e:
                    is_last = attempt >= 2
                    if is_last:
                        logger.warning(
                            "Process video failed: {} (attempt={}/3, {})",
                            orig_url,
                            attempt + 1,
                            f"{type(e).__name__}: {e}",
                        )
                    else:
                        await asyncio.sleep(1.5 * (attempt + 1))
                        continue

            if not (video_bytes and key and sha256_hex):
                continue

            stored_url = storage.get_url(key=key)
            
            vid["stored_key"] = key
            vid["stored_url"] = stored_url
            vid["stored_sha256"] = sha256_hex
            vid["stored_size"] = len(video_bytes)

            stored_videos.append({
                "orig_url": orig_url,
                "key": key,
                "url": stored_url,
                "sha256": sha256_hex,
                "size": len(video_bytes),
            })

            count += 1

    if stored_videos:
        archive["stored_videos"] = stored_videos

    logger.info(
        "Archive videos processed: total_videos={}, stored_videos={}",
        len(videos),
        len(stored_videos),
    )

    return archive
