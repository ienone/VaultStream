"""
Napcat (OneBot 11) 推送服务实现。

提供 QQ 群组/私聊消息推送，支持图片/视频/音频媒体、图文混排和合并转发。

OneBot 11 消息段格式参考: https://docs.ncatbot.xyz/guide/message_segment/
消息发送 API 参考: https://docs.ncatbot.xyz/guide/apimessage/
合并转发参考: https://docs.ncatbot.xyz/guide/forward_constructor/
"""
from __future__ import annotations

from typing import Dict, Any, List, Optional

import httpx

from app.core.logging import logger
from app.core.storage import get_storage_backend
from app.services.bot_config_runtime import get_primary_qq_runtime_from_db
from app.utils.text_formatters import format_content_with_render_config, strip_markdown
from app.media.extractor import extract_media_urls
from .base import BasePushService

MAX_FORWARD_NODES = 99


def _resolve_media_url(media_item: Dict[str, Any]) -> Optional[str]:
    """Resolve a media item to a URL usable by NapCat.

    Priority:
    1. Local file path via stored_key (file:// URI for NapCat on same host)
    2. stored_url / url from the item
    """
    backend = get_storage_backend()

    if media_item.get("stored_key"):
        local_path = backend.get_local_path(key=media_item["stored_key"])
        if local_path:
            return f"file:///{local_path.replace(chr(92), '/')}"

    public_url = backend.get_url(key=media_item["stored_key"]) if media_item.get("stored_key") else None
    if public_url:
        return public_url

    return media_item.get("url")


def _build_text_segment(text: str) -> Dict[str, Any]:
    return {"type": "text", "data": {"text": text}}


def _build_image_segment(url: str) -> Dict[str, Any]:
    return {"type": "image", "data": {"file": url}}


def _build_video_segment(url: str) -> Dict[str, Any]:
    return {"type": "video", "data": {"file": url}}


def _build_record_segment(url: str) -> Dict[str, Any]:
    return {"type": "record", "data": {"file": url}}


class NapcatPushService(BasePushService):
    """Napcat/OneBot 11 推送服务。"""

    def __init__(self):
        self._client: Optional[httpx.AsyncClient] = None
        self._bot_uin: Optional[str] = None

    async def _get_client(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            base_url, access_token, bot_uin = await get_primary_qq_runtime_from_db()
            base_url = base_url.rstrip("/")
            self._bot_uin = bot_uin
            headers = {}
            if access_token:
                headers["Authorization"] = f"Bearer {access_token}"
            self._client = httpx.AsyncClient(base_url=base_url, headers=headers, timeout=30.0)
        return self._client

    async def _post(self, endpoint: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        client = await self._get_client()
        response = await client.post(endpoint, json=payload)
        response.raise_for_status()
        data = response.json()
        if isinstance(data, dict) and data.get("status") not in (None, "ok"):
            raise RuntimeError(f"Napcat API error: {data}")
        return data

    def _get_media_mode(self, content: Dict[str, Any]) -> str:
        render_config = content.get("render_config") or {}
        if isinstance(render_config, dict):
            structure = render_config.get("structure", render_config)
            return structure.get("media_mode", "auto")
        return "auto"

    def _extract_media(self, content: Dict[str, Any]) -> List[Dict[str, Any]]:
        media_mode = self._get_media_mode(content)
        if media_mode == "none":
            return []

        cover_url = content.get("cover_url")
        media_items = content.get("media_items") or []
        if not media_items:
            archive_metadata = content.get("archive_metadata") or {}
            media_items = extract_media_urls(archive_metadata, cover_url)

        if media_mode == "cover" and media_items:
            photos = [m for m in media_items if m["type"] == "photo"]
            return photos[:1] if photos else media_items[:1]

        return media_items

    def _build_message_segments(self, content: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Build OneBot 11 message segments including text and media.

        Produces a mixed-content message array:
        [text, image, image, ..., video, ...]
        """
        render_config = content.get("render_config") or {}
        text = format_content_with_render_config(
            content,
            render_config,
            rich_text=False,
            platform=content.get("platform") or "",
        )
        text = strip_markdown(text)
        if not text:
            text = "(no content)"

        segments: List[Dict[str, Any]] = [_build_text_segment(text)]

        media_items = self._extract_media(content)
        for item in media_items:
            url = _resolve_media_url(item)
            if not url:
                continue
            if item["type"] == "photo":
                segments.append(_build_image_segment(url))
            elif item["type"] == "video":
                segments.append(_build_video_segment(url))

        return segments

    def _parse_target(self, target_id: str):
        target_id = str(target_id)
        is_private = False
        if target_id.startswith("private:"):
            is_private = True
            target_id = target_id.split(":", 1)[1]
        elif target_id.startswith("group:"):
            target_id = target_id.split(":", 1)[1]
        return target_id, is_private

    async def push(self, content: Dict[str, Any], target_id: str) -> Optional[str]:
        """Send a message (text + media) to a QQ target.

        target_id supports:
        - group:123456
        - private:123456
        - 123456 (defaults to group)
        """
        target_id, is_private = self._parse_target(target_id)

        segments = self._build_message_segments(content)
        payload: Dict[str, Any] = {"message": segments}
        if is_private:
            payload["user_id"] = int(target_id)
            endpoint = "/send_private_msg"
        else:
            payload["group_id"] = int(target_id)
            endpoint = "/send_group_msg"

        logger.info(f"Napcat push: target={target_id}, private={is_private}, segments={len(segments)}")
        data = await self._post(endpoint, payload)
        message_id = None
        if isinstance(data, dict):
            message_id = data.get("data", {}).get("message_id")
        return str(message_id) if message_id is not None else None

    async def push_forward(
        self,
        contents: List[Dict[str, Any]],
        target_id: str,
        *,
        use_author_name: bool = True,
        summary: Optional[str] = None,
    ) -> Optional[str]:
        """Send a merged forward message containing multiple content items.

        Each content item becomes a forward node with text + media segments.
        """
        target_id, is_private = self._parse_target(target_id)

        nodes: List[Dict[str, Any]] = []
        for content in contents[:MAX_FORWARD_NODES]:
            name = content.get("author_name") if use_author_name else "VaultStream"
            name = name or "VaultStream"
            node_segments = self._build_message_segments(content)
            node = {
                "type": "node",
                "data": {
                    "name": str(name),
                    "uin": self._bot_uin or "0",
                    "content": node_segments,
                },
            }
            nodes.append(node)

        payload: Dict[str, Any] = {"messages": nodes}
        if summary:
            payload["summary"] = summary

        if is_private:
            payload["user_id"] = int(target_id)
            endpoint = "/send_private_forward_msg"
        else:
            payload["group_id"] = int(target_id)
            endpoint = "/send_group_forward_msg"

        logger.info(f"Napcat forward push: target={target_id}, nodes={len(nodes)}")
        data = await self._post(endpoint, payload)
        message_id = None
        if isinstance(data, dict):
            message_id = data.get("data", {}).get("message_id")
        return str(message_id) if message_id is not None else None

    async def close(self):
        if self._client and not self._client.is_closed:
            await self._client.aclose()
