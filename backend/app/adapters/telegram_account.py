"""Telegram 用户会话读取；不发送消息、不改变通知或已读状态。"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import datetime, timezone

from telethon import TelegramClient, errors, functions, types, utils
from telethon.extensions import html
from markdownify import markdownify


@dataclass(frozen=True)
class MessageAddress:
    peer_id: int  # Telethon marked ID distinguishes users, chats and channels.
    message_id: int

    def as_dict(self) -> dict[str, int]:
        return {"peer_id": self.peer_id, "message_id": self.message_id}


@dataclass
class TelegramPost:
    messages: list[types.Message]
    body: str
    fingerprint: str
    origin: MessageAddress | None
    forwarded: bool
    reply: dict | None

    @property
    def address(self) -> MessageAddress:
        first = self.messages[0]
        return MessageAddress(utils.get_peer_id(first.peer_id), first.id)


def forward_address(message: types.Message) -> MessageAddress | None:
    forward = message.fwd_from
    if not forward:
        return None
    if isinstance(forward.from_id, types.PeerChannel) and forward.channel_post:
        return MessageAddress(utils.get_peer_id(forward.from_id), forward.channel_post)
    if forward.saved_from_peer and forward.saved_from_msg_id:
        return MessageAddress(utils.get_peer_id(forward.saved_from_peer), forward.saved_from_msg_id)
    return None


def notifications_enabled(peer: types.PeerNotifySettings, defaults: types.PeerNotifySettings, now: datetime) -> bool:
    until = peer.mute_until if peer.mute_until is not None else defaults.mute_until
    return until is None or until <= now


def _message_payload(message: types.Message) -> dict:
    # Exclude expiring access hashes/file references and engagement counters.
    media = message.photo or message.document
    reply = message.reply_to
    return {
        "text": message.message or "",
        "entities": [entity.to_dict() for entity in (message.entities or [])],
        "media": {"type": type(media).__name__, "id": media.id} if media else None,
        "reply": reply.to_dict() if reply else None,
    }


def assemble_posts(messages: list[types.Message]) -> list[TelegramPost]:
    groups: dict[tuple[int, int, bool], list[types.Message]] = {}
    for message in sorted(messages, key=lambda item: item.id):
        if message.action or not (message.message or message.media):
            continue
        key = (utils.get_peer_id(message.peer_id), message.grouped_id or message.id, bool(message.grouped_id))
        groups.setdefault(key, []).append(message)
    posts = []
    for members in groups.values():
        texts = [markdownify(html.unparse(m.message or "", m.entities or []), heading_style="ATX").strip() for m in members if m.message]
        payload = [_message_payload(m) for m in members]
        fingerprint = hashlib.sha256(json.dumps(payload, sort_keys=True, ensure_ascii=False, default=str).encode()).hexdigest()
        reply = members[0].reply_to
        reply_data = None
        if isinstance(reply, types.MessageReplyHeader):
            reply_data = {
                "peer_id": utils.get_peer_id(reply.reply_to_peer_id or members[0].peer_id),
                "message_id": reply.reply_to_msg_id,
                "quote_text": reply.quote_text,
            }
        posts.append(TelegramPost(
            members, "\n\n".join(dict.fromkeys(texts)), fingerprint,
            forward_address(members[0]), bool(members[0].fwd_from), reply_data,
        ))
    return posts


class TelegramAccountReader:
    def __init__(self, client: TelegramClient):
        self.client = client

    async def subscribed_channels(self) -> list[dict]:
        defaults = await self.client(functions.account.GetNotifySettingsRequest(types.InputNotifyBroadcasts()))
        now = datetime.now(timezone.utc)
        channels = []
        async for dialog in self.client.iter_dialogs():
            entity = dialog.entity
            if not isinstance(entity, types.Channel) or not entity.broadcast or entity.left:
                continue
            channels.append({
                "peer_id": dialog.id,
                "title": dialog.title,
                "username": entity.username,
                "notifications_enabled": notifications_enabled(dialog.dialog.notify_settings, defaults, now),
            })
        return channels

    async def read_page(self, peer, *, after: int | None, limit: int = 100) -> tuple[list[TelegramPost], int | None]:
        """Read a bounded page, extending its last album before returning a cursor.

        Initial reads take recent history; subsequent reads go oldest-first so
        a busy channel cannot skip the middle of its backlog.
        """
        if not 1 <= limit <= 500:
            raise ValueError("Telegram page size must be between 1 and 500")
        messages = []
        boundary_group = None
        high_water = after
        async for message in self.client.iter_messages(peer, min_id=after or 0, reverse=after is not None):
            if len(messages) >= limit:
                if not boundary_group or message.grouped_id != boundary_group:
                    break
            messages.append(message)
            boundary_group = message.grouped_id
            high_water = max(high_water or 0, message.id)
        return assemble_posts(messages), high_water

    async def source_chain(self, message: types.Message, *, max_hops: int = 16) -> list[dict]:
        """Only expose resolvable sources; inaccessible upstream is simply absent."""
        chain = []
        seen = {MessageAddress(utils.get_peer_id(message.peer_id), message.id)}
        current = message
        for _ in range(max_hops):
            address = forward_address(current)
            if address is None or address in seen:
                break
            seen.add(address)
            try:
                entity = await self.client.get_entity(address.peer_id)
                upstream = await self.client.get_messages(entity, ids=address.message_id)
            except (ValueError, errors.ChannelPrivateError, errors.ChannelInvalidError, errors.MsgIdInvalidError):
                break
            if not isinstance(upstream, types.Message) or upstream.action:
                break
            username = getattr(entity, "username", None)
            link = None
            if username:
                link = f"https://t.me/{username}/{address.message_id}"
            elif isinstance(entity, types.Channel):
                link = f"https://t.me/c/{entity.id}/{address.message_id}"
            chain.append({**address.as_dict(), "name": utils.get_display_name(entity), "url": link})
            current = upstream
        return chain
