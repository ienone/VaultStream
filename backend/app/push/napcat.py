"""
Napcat (OneBot 11) 推送服务实现。

提供 QQ 群组/私聊消息推送，支持合并转发。
"""
from __future__ import annotations

from typing import Dict, Any, List, Optional

import httpx

from app.core.config import settings
from app.core.logging import logger
from app.utils.text_formatters import format_content_with_render_config
from .base import BasePushService

MAX_FORWARD_NODES = 99


class NapcatPushService(BasePushService):
    """Napcat/OneBot 11 推送服务。"""

    def __init__(self):
        self._client: Optional[httpx.AsyncClient] = None

    async def _get_client(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            base_url = settings.napcat_api_base.rstrip("/")
            headers = {}
            if settings.napcat_access_token:
                headers["Authorization"] = f"Bearer {settings.napcat_access_token.get_secret_value()}"
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

    def _build_message_segments(self, content: Dict[str, Any]) -> List[Dict[str, Any]]:
        render_config = content.get("render_config") or {}
        text = format_content_with_render_config(
            content,
            render_config,
            rich_text=False,
            platform=content.get("platform") or "",
        )
        if not text:
            text = "(no content)"
        return [{"type": "text", "data": {"text": text}}]

    async def push(self, content: Dict[str, Any], target_id: str) -> Optional[str]:
        """
        向 QQ 目标发送消息。

        target_id 支持:
        - group:123456
        - private:123456
        - 123456 (默认为群组)
        """
        target_id = str(target_id)
        is_private = False
        if target_id.startswith("private:"):
            is_private = True
            target_id = target_id.split(":", 1)[1]
        elif target_id.startswith("group:"):
            target_id = target_id.split(":", 1)[1]

        segments = self._build_message_segments(content)
        payload = {"message": segments}
        if is_private:
            payload["user_id"] = int(target_id)
            endpoint = "/send_private_msg"
        else:
            payload["group_id"] = int(target_id)
            endpoint = "/send_group_msg"

        logger.info(f"Napcat push: target={target_id}, private={is_private}")
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
        target_id = str(target_id)
        is_private = False
        if target_id.startswith("private:"):
            is_private = True
            target_id = target_id.split(":", 1)[1]
        elif target_id.startswith("group:"):
            target_id = target_id.split(":", 1)[1]

        nodes = []
        for content in contents[:MAX_FORWARD_NODES]:
            name = content.get("author_name") if use_author_name else "VaultStream"
            name = name or "VaultStream"
            node = {
                "type": "node",
                "data": {
                    "name": str(name),
                    "uin": settings.napcat_bot_uin,
                    "content": self._build_message_segments(content),
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
