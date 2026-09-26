"""旧 HTTP 收录入口仅处理私聊；群链接统一由 Koishi 公开预览。"""
import json
from sqlalchemy import select
from app.adapters import AdapterFactory
from app.core.database import AsyncSessionLocal
from app.models import BotChat, ContentSource
from app.push.napcat import NapcatPushService
from app.services.config_service import ConfigService
from app.services.content_service import ContentService
from app.utils.url_utils import extract_urls_from_text


async def message_text(segments, api, depth=0):
    if depth > 5:
        return ''
    if isinstance(segments, str):
        return segments
    pieces = []
    for segment in segments or []:
        kind, data = segment.get('type'), segment.get('data', {})
        if kind == 'text':
            pieces.append(data.get('text', ''))
        elif kind == 'json':
            card = json.loads(data.get('data', '{}'))
            def links(value):
                if isinstance(value, dict):
                    for key, item in value.items():
                        if key.lower() in {'qqdocurl', 'jumpurl', 'url', 'appurl'} and isinstance(item, str):
                            pieces.append(item)
                        else:
                            links(item)
                elif isinstance(value, list):
                    for item in value:
                        links(item)
            links(card)
        elif kind == 'forward':
            result = await api._post('/get_forward_msg', {'message_id': data['id']})
            for node in result['data']['messages']:
                pieces.append(await message_text(node.get('content', []), api, depth + 1))
        elif kind == 'node':
            pieces.append(await message_text(data.get('content', []), api, depth + 1))
        elif kind == 'reply':
            result = await api._post('/get_msg', {'message_id': data['id']})
            pieces.append(await message_text(result['data']['message'], api, depth + 1))
    return '\n'.join(pieces)


async def accept_message(config_id, event):
    # Group messages must never enter the collection, even if an old
    # BotChat.is_monitoring flag is still enabled. Koishi owns group previews.
    if (event.get('post_type') != 'message' or event.get('message_type') != 'private'
            or str(event.get('user_id')) == str(event.get('self_id'))):
        return [], None
    raw_id = str(event.get('user_id'))
    target = f'private:{raw_id}'
    async with AsyncSessionLocal() as db:
        chat = await db.scalar(select(BotChat).where(
            BotChat.bot_config_id == config_id, BotChat.chat_id == target,
            BotChat.enabled.is_(True), BotChat.is_monitoring.is_(True)))
        if not chat:
            return [], None
        context = {'bot_config_id': config_id, 'chat_id': target, 'message_id': event['message_id']}
        duplicate = await db.scalar(select(ContentSource.id).where(
            ContentSource.source == 'qq_bot',
            ContentSource.client_context['bot_config_id'].as_integer() == config_id,
            ContentSource.client_context['chat_id'].as_string() == target,
            ContentSource.client_context['message_id'].as_integer() == int(event['message_id'])))
        if duplicate:
            return [], None
    api = NapcatPushService()
    try:
        text = await message_text(event.get('message', []), api)
    finally:
        if api._client:
            await api._client.aclose()
    urls = list(dict.fromkeys(extract_urls_from_text(text)))
    policy = (await ConfigService().get_value('qq_chat_policies', {})).get(raw_id, {})
    excluded = policy.get('excluded_parse_platforms', [])
    ids = []
    async with AsyncSessionLocal() as db:
        service = ContentService(db)
        for url in urls[:20]:
            platform = AdapterFactory.detect_platform(url)
            if platform is None or platform.value in excluded:
                continue
            content = await service.create_share(url, source_name='qq_bot', client_context=context)
            ids.append(content.id)
        if not urls and text.strip():
            content = await service.create_text_capture(text=text, source_name='qq_bot', client_context=context)
            ids.append(content.id)
    return ids, target
