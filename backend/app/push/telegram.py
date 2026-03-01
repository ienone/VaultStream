"""
Telegram推送服务实现

提供完整的Telegram消息推送功能,包括文本、图片、视频等
"""
import httpx
import os
from typing import Dict, Any, List, Tuple, Optional
from contextlib import ExitStack

from telegram import Bot, InputMediaPhoto, InputMediaVideo
from telegram.request import HTTPXRequest
from telegram.error import TelegramError

from app.core.logging import logger
from app.core.config import settings
from app.adapters.storage import get_storage_backend
from app.services.bot_config_runtime import get_primary_telegram_token_from_db
from app.utils.text_formatters import format_content_for_tg, format_content_with_render_config
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
            bot_token = await get_primary_telegram_token_from_db()
            
            # 配置代理 (通过环境变量，httpx 会自动读取)
            from app.services.settings_service import get_setting_value
            proxy = await get_setting_value("http_proxy", getattr(settings, 'http_proxy', None))
            
            if proxy:
                os.environ['HTTP_PROXY'] = proxy
                os.environ['HTTPS_PROXY'] = proxy
                logger.debug(f"已设置代理环境变量: {proxy}")
            
            request = HTTPXRequest(
                connect_timeout=10.0,
                read_timeout=30.0,
                write_timeout=60.0
            )
            
            self._bot = Bot(
                token=bot_token,
                request=request
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
    
    @staticmethod
    def _get_media_mode(render_config: Dict[str, Any]) -> str:
        if not render_config:
            return "auto"
        structure = render_config.get("structure", render_config)
        return structure.get("media_mode", "auto")

    def _build_payload(self, content: Dict[str, Any]) -> Tuple[str, List[Dict]]:
        """
        构建 Telegram 发送载荷
        
        Args:
            content: 内容数据（包含 title, archive_metadata 等）
        
        Returns:
            Tuple[str, List[Dict]]: (格式化后的文本, 媒体项列表)
        """
        render_config = content.get('render_config') or {}
        if render_config:
            text = format_content_with_render_config(
                content,
                render_config,
                rich_text=True,
                platform=content.get('platform') or "",
            )
        else:
            text = format_content_for_tg(content)
        
        cover_url = content.get('cover_url')
        media_items = content.get('media_items') or []
        if not media_items:
            archive_metadata = content.get('archive_metadata', {})
            media_items = extract_media_urls(archive_metadata, cover_url)

        media_mode = self._get_media_mode(render_config)
        if media_mode == "none":
            media_items = []
        elif media_mode == "cover" and media_items:
            photos = [m for m in media_items if m["type"] == "photo"]
            media_items = photos[:1] if photos else media_items[:1]

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
        backend = get_storage_backend()
        
        with ExitStack() as stack:
            media_group = []
            for idx, item in enumerate(media_items[:MAX_MEDIA_GROUP_SIZE]):
                media = item['url']
                # 尝试使用本地文件
                if item.get('stored_key'):
                     local_path = backend.get_local_path(key=item['stored_key'])
                     if local_path:
                         try:
                             media = stack.enter_context(open(local_path, 'rb'))
                             logger.debug(f"使用本地媒体文件: {local_path}")
                         except Exception as e:
                             logger.warning(f"无法打开本地文件 {local_path}: {e}")

                if item['type'] == 'photo':
                    if idx == 0:
                        media_group.append(InputMediaPhoto(media=media, caption=text, parse_mode='HTML'))
                    else:
                        media_group.append(InputMediaPhoto(media=media))
                elif item['type'] == 'video':
                    if idx == 0:
                        media_group.append(InputMediaVideo(media=media, caption=text, parse_mode='HTML'))
                    else:
                        media_group.append(InputMediaVideo(media=media))
            
            try:
                messages = await bot.send_media_group(
                    chat_id=chat_id,
                    media=media_group,
                    read_timeout=120,
                    write_timeout=120
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
        backend = get_storage_backend()
        media = media_item['url']
        file_handle = None
        
        # 尝试使用本地文件
        if media_item.get('stored_key'):
             local_path = backend.get_local_path(key=media_item['stored_key'])
             if local_path:
                 try:
                     file_handle = open(local_path, 'rb')
                     media = file_handle
                     logger.debug(f"使用本地媒体文件: {local_path}")
                 except Exception as e:
                     logger.warning(f"无法打开本地文件 {local_path}: {e}")

        try:
            if media_item['type'] == 'photo':
                return await bot.send_photo(
                    chat_id=chat_id,
                    photo=media,
                    caption=caption,
                    parse_mode='HTML',
                    read_timeout=60,
                    write_timeout=60,
                    reply_markup=reply_markup
                )
            elif media_item['type'] == 'video':
                return await bot.send_video(
                    chat_id=chat_id,
                    video=media,
                    caption=caption,
                    parse_mode='HTML',
                    read_timeout=120,
                    write_timeout=120,
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
        finally:
            if file_handle:
                file_handle.close()
    
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
            logger.info(f"准备发送至 Telegram: target={target_id}, media_count={len(media_items)}, text_len={len(text)}")
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
