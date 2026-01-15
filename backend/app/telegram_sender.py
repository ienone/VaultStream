"""
Telegram 发送公共模块
统一处理 Telegram 消息发送逻辑
"""
from typing import Dict, Any, List, Tuple, Optional

from telegram import InputMediaPhoto, InputMediaVideo
from telegram.error import TelegramError

from app.logging import logger
from app.utils import format_content_for_tg
from app.media_utils import extract_media_urls

MAX_CAPTION_LENGTH = 1024
MAX_MESSAGE_LENGTH = 4096
MAX_MEDIA_GROUP_SIZE = 10


def build_telegram_payload(content: Dict[str, Any]) -> Tuple[str, List[Dict]]:
    """
    构建 Telegram 发送载荷
    
    Args:
        content: 内容数据（包含 title, raw_metadata 等）
    
    Returns:
        Tuple[str, List[Dict]]: (格式化后的文本, 媒体项列表)
    """
    text = format_content_for_tg(content)
    
    raw_metadata = content.get('raw_metadata', {})
    cover_url = content.get('cover_url')
    media_items = extract_media_urls(raw_metadata, cover_url)
    
    if media_items and len(text) > MAX_CAPTION_LENGTH:
        text = text[:MAX_CAPTION_LENGTH - 3] + "..."
    elif not media_items and len(text) > MAX_MESSAGE_LENGTH:
        text = text[:MAX_MESSAGE_LENGTH - 3] + "..."
    
    return text, media_items


async def send_to_telegram(
    bot,
    chat_id: str,
    text: str,
    media_items: List[Dict],
    reply_markup=None
) -> Optional[int]:
    """
    统一的 Telegram 发送函数
    
    Args:
        bot: Telegram Bot 实例
        chat_id: 目标频道/群组ID
        text: 发送的文本
        media_items: 媒体项列表 [{'type': 'photo'|'video', 'url': '...'}]
        reply_markup: 可选的按钮键盘
    
    Returns:
        message_id: 成功返回消息ID，失败返回 None
    """
    try:
        message = None
        
        if len(media_items) > 1:
            message = await _send_media_group(bot, chat_id, text, media_items, reply_markup)
        elif len(media_items) == 1:
            message = await _send_single_media(bot, chat_id, media_items[0], text, reply_markup)
        else:
            message = await bot.send_message(
                chat_id=chat_id,
                text=text,
                parse_mode='HTML',
                disable_web_page_preview=False,
                reply_markup=reply_markup
            )
        
        if message:
            return message.message_id
        return None
        
    except TelegramError as e:
        logger.error(f"Telegram 发送失败: {e}")
        return None
    except Exception as e:
        logger.exception(f"发送失败: {e}")
        return None


async def _send_media_group(
    bot,
    chat_id: str,
    text: str,
    media_items: List[Dict],
    reply_markup=None
):
    """发送媒体组"""
    media_group = []
    for idx, item in enumerate(media_items[:MAX_MEDIA_GROUP_SIZE]):
        if item['type'] == 'photo':
            if idx == 0:
                media_group.append(InputMediaPhoto(media=item['url'], caption=text, parse_mode='HTML'))
            else:
                media_group.append(InputMediaPhoto(media=item['url']))
        elif item['type'] == 'video':
            if idx == 0:
                media_group.append(InputMediaVideo(media=item['url'], caption=text, parse_mode='HTML'))
            else:
                media_group.append(InputMediaVideo(media=item['url']))
    
    try:
        messages = await bot.send_media_group(
            chat_id=chat_id,
            media=media_group,
            read_timeout=60,
            write_timeout=60
        )
        if messages:
            if reply_markup:
                await bot.send_message(
                    chat_id=chat_id,
                    text="管理操作:",
                    reply_to_message_id=messages[0].message_id,
                    reply_markup=reply_markup
                )
            return messages[0]
        return None
    except TelegramError as e:
        logger.warning(f"发送媒体组失败，降级为单个媒体: {e}")
        return await _send_single_media(bot, chat_id, media_items[0], text, reply_markup)


async def _send_single_media(
    bot,
    chat_id: str,
    media_item: Dict,
    caption: str,
    reply_markup=None
):
    """发送单个媒体"""
    try:
        if media_item['type'] == 'photo':
            return await bot.send_photo(
                chat_id=chat_id,
                photo=media_item['url'],
                caption=caption,
                parse_mode='HTML',
                read_timeout=30,
                write_timeout=30,
                reply_markup=reply_markup
            )
        elif media_item['type'] == 'video':
            return await bot.send_video(
                chat_id=chat_id,
                video=media_item['url'],
                caption=caption,
                parse_mode='HTML',
                read_timeout=60,
                write_timeout=60,
                reply_markup=reply_markup
            )
    except TelegramError as e:
        logger.warning(f"发送单个媒体失败，降级为文本: {e}")
        return await bot.send_message(
            chat_id=chat_id,
            text=caption,
            parse_mode='HTML',
            disable_web_page_preview=False,
            reply_markup=reply_markup
        )
