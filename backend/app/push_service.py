"""
推送服务 - 用于自动推送模式
将内容推送到 Telegram 频道
"""
import httpx
from typing import Optional, Dict, Any
from telegram import Bot, InputMediaPhoto, InputMediaVideo
from telegram.error import TelegramError
from app.logging import logger
from app.config import settings
from app.utils import format_content_for_tg
from app.media_utils import extract_media_urls


class PushService:
    """推送服务 - 负责将内容推送到各个平台"""
    
    def __init__(self):
        self._bot: Optional[Bot] = None
        self._http_client: Optional[httpx.AsyncClient] = None
    
    async def _get_bot(self) -> Bot:
        """获取或创建 Telegram Bot 实例"""
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
        """获取或创建 HTTP 客户端"""
        if self._http_client is None or self._http_client.is_closed:
            self._http_client = httpx.AsyncClient(timeout=30.0)
        return self._http_client
    
    async def close(self):
        """关闭连接"""
        if self._http_client and not self._http_client.is_closed:
            await self._http_client.aclose()
    
    async def push_to_telegram(
        self, 
        content: Dict[str, Any], 
        target_id: str
    ) -> Optional[int]:
        """
        推送内容到 Telegram 频道/群组
        
        Args:
            content: 内容数据（包含 title, raw_metadata 等）
            target_id: 目标频道/群组ID（如 @my_channel 或 -100123456789）
        
        Returns:
            message_id: 成功返回消息ID，失败返回 None
        """
        try:
            bot = await self._get_bot()
            
            # 格式化文本
            text = format_content_for_tg(content)
            max_caption_length = 1024
            max_message_length = 4096
            
            # 提取媒体URL（使用优化后的工具函数）
            raw_metadata = content.get('raw_metadata', {})
            cover_url = content.get('cover_url')
            media_items = extract_media_urls(raw_metadata, cover_url)
            
            # 处理文本长度
            if media_items and len(text) > max_caption_length:
                text = text[:max_caption_length-3] + "..."
            elif not media_items and len(text) > max_message_length:
                text = text[:max_message_length-3] + "..."
            
            message = None
            
            # 如果有多个媒体，使用 media group
            if len(media_items) > 1:
                media_group = []
                for idx, item in enumerate(media_items[:10]):  # Telegram 限制最多10个媒体
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
                        chat_id=target_id,
                        media=media_group,
                        read_timeout=60,
                        write_timeout=60
                    )
                    # 返回第一条消息的ID
                    message = messages[0] if messages else None
                except TelegramError as e:
                    logger.warning(f"发送媒体组失败，降级为单个媒体: {e}")
                    message = await self._send_single_media(bot, target_id, media_items[0], text)
                    
            elif len(media_items) == 1:
                # 只有一个媒体
                message = await self._send_single_media(bot, target_id, media_items[0], text)
            else:
                # 没有媒体，纯文本
                message = await bot.send_message(
                    chat_id=target_id,
                    text=text,
                    parse_mode='HTML',
                    disable_web_page_preview=False
                )
            
            if message:
                logger.info(f"成功推送到 Telegram: target_id={target_id}, message_id={message.message_id}")
                return message.message_id
            else:
                logger.error(f"推送失败，未获取到消息ID: target_id={target_id}")
                return None
                
        except TelegramError as e:
            logger.error(f"Telegram 推送失败: {e}")
            return None
        except Exception as e:
            logger.exception(f"推送失败: {e}")
            return None
    
    async def _send_single_media(
        self, 
        bot: Bot, 
        target_id: str, 
        media_item: dict, 
        caption: str
    ):
        """发送单个媒体"""
        try:
            if media_item['type'] == 'photo':
                return await bot.send_photo(
                    chat_id=target_id,
                    photo=media_item['url'],
                    caption=caption,
                    parse_mode='HTML',
                    read_timeout=30,
                    write_timeout=30
                )
            elif media_item['type'] == 'video':
                return await bot.send_video(
                    chat_id=target_id,
                    video=media_item['url'],
                    caption=caption,
                    parse_mode='HTML',
                    read_timeout=60,
                    write_timeout=60
                )
        except TelegramError as e:
            logger.warning(f"发送单个媒体失败，降级为文本: {e}")
            return await bot.send_message(
                chat_id=target_id,
                text=caption,
                parse_mode='HTML',
                disable_web_page_preview=False
            )


# 全局单例
_push_service: Optional[PushService] = None


def get_push_service() -> PushService:
    """获取推送服务单例"""
    global _push_service
    if _push_service is None:
        _push_service = PushService()
    return _push_service
