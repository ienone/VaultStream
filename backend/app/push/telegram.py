"""
Telegram推送服务实现

提供完整的Telegram消息推送功能,包括文本、图片、视频等
"""
import httpx
from typing import Dict, Any, List, Tuple, Optional

from telegram import Bot, InputMediaPhoto, InputMediaVideo
from telegram.error import TelegramError

from app.core.logging import logger
from app.core.config import settings
from app.utils.text_formatters import format_content_for_tg
from app.media.extractor import extract_media_urls
from .base import BasePushService


# Telegram限制常量
MAX_CAPTION_LENGTH = 1024
MAX_MESSAGE_LENGTH = 4096
MAX_MEDIA_GROUP_SIZE = 10


class TelegramPushService(BasePushService):
    """
    Telegram推送服务
    
    负责将内容推送到Telegram频道或群组
    支持文本、图片、视频等多种媒体类型
    """
    
    def __init__(self):
        """初始化Telegram推送服务"""
        self._bot: Optional[Bot] = None
        self._http_client: Optional[httpx.AsyncClient] = None
    
    async def _get_bot(self) -> Bot:
        """
        获取或创建 Telegram Bot 实例
        
        Returns:
            Telegram Bot实例
        """
        if self._bot is None:
            bot_token = settings.telegram_bot_token.get_secret_value()
            
            # 配置代理
            proxy_url = None
            if hasattr(settings, 'http_proxy') and settings.http_proxy:
                proxy_url = settings.http_proxy
            
            self._bot = Bot(
                token=bot_token,
                proxy_url=proxy_url,
                connect_timeout=10,
                read_timeout=30,
                write_timeout=60
            )
        return self._bot
    
    async def _get_http_client(self) -> httpx.AsyncClient:
        """
        获取或创建 HTTP 客户端
        
        Returns:
            httpx异步客户端
        """
        if self._http_client is None or self._http_client.is_closed:
            self._http_client = httpx.AsyncClient(timeout=30.0)
        return self._http_client
    
    def _build_payload(self, content: Dict[str, Any]) -> Tuple[str, List[Dict]]:
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
        
        # 根据是否有媒体调整文本长度
        if media_items and len(text) > MAX_CAPTION_LENGTH:
            text = text[:MAX_CAPTION_LENGTH - 3] + "..."
        elif not media_items and len(text) > MAX_MESSAGE_LENGTH:
            text = text[:MAX_MESSAGE_LENGTH - 3] + "..."
        
        return text, media_items
    
    async def _send_media_group(
        self,
        bot: Bot,
        chat_id: str,
        text: str,
        media_items: List[Dict],
        reply_markup=None
    ):
        """
        发送媒体组（多张图片或视频）
        
        Args:
            bot: Telegram Bot实例
            chat_id: 目标聊天ID
            text: 附带文本
            media_items: 媒体项列表
            reply_markup: 可选的按钮键盘
            
        Returns:
            第一条消息对象，失败返回None
        """
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
                # 如果有按钮,发送一条回复消息
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
            # 降级处理：只发送第一个媒体
            return await self._send_single_media(bot, chat_id, media_items[0], text, reply_markup)
    
    async def _send_single_media(
        self,
        bot: Bot,
        chat_id: str,
        media_item: Dict,
        caption: str,
        reply_markup=None
    ):
        """
        发送单个媒体（图片或视频）
        
        Args:
            bot: Telegram Bot实例
            chat_id: 目标聊天ID
            media_item: 媒体项字典
            caption: 附带文本
            reply_markup: 可选的按钮键盘
            
        Returns:
            消息对象，失败返回None
        """
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
            # 降级为纯文本消息
            return await bot.send_message(
                chat_id=chat_id,
                text=caption,
                parse_mode='HTML',
                disable_web_page_preview=False,
                reply_markup=reply_markup
            )
    
    async def push(
        self, 
        content: Dict[str, Any], 
        target_id: str,
        reply_markup=None
    ) -> Optional[str]:
        """
        推送内容到 Telegram 频道/群组
        
        Args:
            content: 内容字典
            target_id: 目标频道/群组ID
            reply_markup: 可选的按钮键盘
        
        Returns:
            成功返回消息ID，失败返回 None
        """
        try:
            bot = await self._get_bot()
            text, media_items = self._build_payload(content)
            
            message = None
            
            # 根据媒体数量选择发送方式
            if len(media_items) > 1:
                message = await self._send_media_group(bot, target_id, text, media_items, reply_markup)
            elif len(media_items) == 1:
                message = await self._send_single_media(bot, target_id, media_items[0], text, reply_markup)
            else:
                # 纯文本消息
                message = await bot.send_message(
                    chat_id=target_id,
                    text=text,
                    parse_mode='HTML',
                    disable_web_page_preview=False,
                    reply_markup=reply_markup
                )
            
            if message:
                message_id = str(message.message_id)
                logger.info(f"成功推送到 Telegram: target_id={target_id}, message_id={message_id}")
                return message_id
            else:
                logger.error(f"推送失败，未获取到消息ID: target_id={target_id}")
                return None
                
        except TelegramError as e:
            logger.error(f"Telegram 发送失败: {e}")
            return None
        except Exception as e:
            logger.exception(f"推送失败: {e}")
            return None
    
    async def close(self):
        """关闭服务连接"""
        if self._http_client and not self._http_client.is_closed:
            await self._http_client.aclose()


# 辅助函数：保持向后兼容
async def build_telegram_payload(content: Dict[str, Any]) -> Tuple[str, List[Dict]]:
    """
    构建 Telegram 发送载荷（向后兼容函数）
    
    Args:
        content: 内容数据
        
    Returns:
        (格式化后的文本, 媒体项列表)
    """
    service = TelegramPushService()
    return service._build_payload(content)


async def send_to_telegram(
    bot,
    chat_id: str,
    text: str,
    media_items: List[Dict],
    reply_markup=None
) -> Optional[int]:
    """
    统一的 Telegram 发送函数（向后兼容）
    
    Args:
        bot: Telegram Bot 实例
        chat_id: 目标频道/群组ID
        text: 发送的文本
        media_items: 媒体项列表
        reply_markup: 可选的按钮键盘
    
    Returns:
        message_id: 成功返回消息ID，失败返回 None
    """
    service = TelegramPushService()
    service._bot = bot
    
    # 构造临时content字典
    content = {
        'raw_metadata': {'archive': {'images': [{'url': item['url']} for item in media_items if item['type'] == 'photo']}}
    }
    
    try:
        # 根据媒体数量选择发送方式
        message = None
        if len(media_items) > 1:
            message = await service._send_media_group(bot, chat_id, text, media_items, reply_markup)
        elif len(media_items) == 1:
            message = await service._send_single_media(bot, chat_id, media_items[0], text, reply_markup)
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
    except Exception as e:
        logger.exception(f"发送失败: {e}")
        return None
