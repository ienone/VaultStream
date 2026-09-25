"""
Telegram推送服务实现

提供完整的Telegram消息推送功能,包括文本、图片、视频等
"""
import html
from io import BytesIO
from pathlib import Path
from urllib.parse import urlsplit
from bs4 import BeautifulSoup
from PIL import Image, ImageOps
import os
from typing import Dict, Any, List, Tuple, Optional
from contextlib import ExitStack

from telegram import Bot, InputMediaPhoto, InputMediaVideo, InputMediaAudio, InputMediaDocument
from telegram.request import HTTPXRequest
from telegram.error import TelegramError

from app.core.logging import logger
from app.adapters.storage import get_storage_backend
from app.services.bot_config_runtime import get_primary_telegram_token_from_db
from app.services.config_service import ConfigService
from app.utils.text_formatters import format_push_text, select_push_media
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
    
    async def _get_bot(self) -> Bot:
        """
        获取或创建 Telegram Bot 实例
        
        Returns:
            Telegram Bot实例
        """
        if self._bot is None:
            bot_token = await get_primary_telegram_token_from_db()
            
            # 配置代理 (通过环境变量，httpx 会自动读取)
            proxy = await ConfigService().get_http_proxy()
            
            if proxy:
                os.environ['HTTP_PROXY'] = proxy
                os.environ['HTTPS_PROXY'] = proxy
            
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
    
    @staticmethod
    def _normalize_target_id(target_id: str) -> str:
        target = str(target_id or "").strip()
        if not target:
            return target
        if target.startswith("@"):
            return target
        if target.lstrip("-").isdigit():
            return target
        return f"@{target}"

    def _build_payload(self, content: Dict[str, Any]) -> Tuple[str, List[Dict]]:
        """
        构建 Telegram 发送载荷
        
        Args:
            content: 内容数据（媒体已由分发器按资产契约选出）
        
        Returns:
            Tuple[str, List[Dict]]: (格式化后的文本, 媒体项列表)
        """
        return format_push_text(content, rich_text=True), select_push_media(content)

    @staticmethod
    def _prepare_media(item, stack):
        kind = item["type"]
        if item.get("stored_key"):
            path = get_storage_backend().get_local_path(key=item["stored_key"])
            if not path:
                raise ValueError("Media storage has no local upload path")
            media = stack.enter_context(open(path, "rb"))
            if kind == "photo":
                with Image.open(path) as image:
                    if getattr(image, "is_animated", False):
                        # Keep animation intact; the stored master is not rewritten.
                        kind = "document"
                    else:
                        image = ImageOps.exif_transpose(image).convert("RGB")
                        width, height = image.size
                        if max(width, height) > 20 * min(width, height):
                            kind = "document"
                        else:
                            image.thumbnail((4096, 4096))
                            upload = stack.enter_context(BytesIO())
                            upload.name = "image.jpg"
                            image.save(upload, "JPEG", quality=90)
                            upload.seek(0)
                            media = upload
            if kind == "audio" and Path(path).suffix.lower() not in {".mp3", ".m4a"}:
                kind = "document"
            if kind == "video" and Path(path).suffix.lower() != ".mp4":
                kind = "document"
        else:
            media = item.get("url")
            if not media or urlsplit(media).scheme not in {"https", "http"}:
                raise ValueError("Media asset has no upload source")
        return kind, media

    async def _send_payload(self, bot, chat_id, text, items, reply_markup):
        # Resolve all local files before making any externally visible sends.
        with ExitStack() as stack:
            media = [self._prepare_media(item, stack) for item in items]
            limit = MAX_CAPTION_LENGTH if media else MAX_MESSAGE_LENGTH
            document = BeautifulSoup(text, "html.parser")
            for link in document.find_all("a", href=True):
                link.replace_with(link["href"])
            plain = document.get_text()
            caption = text
            first = None
            if len(plain.encode("utf-16-le")) // 2 > limit:
                # Long text goes into complete messages, without slicing HTML tags.
                caption = ""
                chunks, current, size = [], [], 0
                for char in plain:
                    units = len(char.encode("utf-16-le")) // 2
                    if size + units > MAX_MESSAGE_LENGTH:
                        value = "".join(current)
                        boundary = value.rfind("\n")
                        if boundary > len(value) // 2:
                            chunks.append(value[:boundary].rstrip())
                            current = list(value[boundary + 1:])
                            size = len("".join(current).encode("utf-16-le")) // 2
                        else:
                            chunks.append(value)
                            current, size = [], 0
                    current.append(char)
                    size += units
                if current:
                    chunks.append("".join(current))
                for chunk in chunks:
                    message = await bot.send_message(
                        chat_id=chat_id, text=html.escape(chunk), parse_mode="HTML",
                        disable_web_page_preview=True, reply_markup=reply_markup if first is None else None,
                    )
                    first = first or message
            if not media:
                if first:
                    return first
                return await bot.send_message(chat_id=chat_id, text=text, parse_mode="HTML", disable_web_page_preview=True, reply_markup=reply_markup)
            constructors = {"photo": InputMediaPhoto, "video": InputMediaVideo,
                            "audio": InputMediaAudio, "document": InputMediaDocument}
            offset = 0
            while offset < len(media):
                kind = media[offset][0]
                family = {"photo", "video"} if kind in {"photo", "video"} else {kind}
                batch = []
                while offset < len(media) and len(batch) < MAX_MEDIA_GROUP_SIZE and media[offset][0] in family:
                    batch.append(media[offset])
                    offset += 1
                if len(batch) == 1:
                    kind, source = batch[0]
                    message = await getattr(bot, f"send_{kind}")(
                        chat_id=chat_id, **{kind: source}, caption=caption or None,
                        parse_mode="HTML", read_timeout=120, write_timeout=120,
                        reply_markup=reply_markup if first is None else None,
                    )
                else:
                    album = [constructors[k](media=source, caption=caption if i == 0 else None,
                                             parse_mode="HTML") for i, (k, source) in enumerate(batch)]
                    messages = await bot.send_media_group(chat_id=chat_id, media=album,
                                                         read_timeout=120, write_timeout=120)
                    message = messages[0]
                    if first is None and reply_markup:
                        await bot.send_message(chat_id=chat_id, text="操作", reply_to_message_id=message.message_id,
                                               reply_markup=reply_markup)
                first = first or message
                caption = ""
            return first

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
        normalized_target_id = self._normalize_target_id(target_id)
        try:
            bot = await self._get_bot()
            text, media_items = self._build_payload(content)
            
            message = await self._send_payload(
                bot, normalized_target_id, text, media_items, reply_markup
            )

            if message:
                message_id = str(message.message_id)
                logger.info(
                    f"成功推送到 Telegram: target_id={normalized_target_id}, "
                    f"message_id={message_id}"
                )
                return message_id
            else:
                logger.error(
                    f"推送失败，未获取到消息ID: target_id={normalized_target_id}, "
                    f"raw_target={target_id}"
                )
                return None
                
        except TelegramError as e:
            logger.error(
                f"Telegram 发送失败: {e}; target_id={normalized_target_id}, raw_target={target_id}"
            )
            return None
        except Exception as e:
            logger.exception(
                f"推送失败: {e}; target_id={normalized_target_id}, raw_target={target_id}"
            )
            return None
    
    async def close(self):
        if self._bot:
            await self._bot.shutdown()
