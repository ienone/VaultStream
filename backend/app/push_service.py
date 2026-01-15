"""
推送服务 - 用于自动推送模式
将内容推送到 Telegram 频道
"""
import httpx
from typing import Optional, Dict, Any
from telegram import Bot
from app.logging import logger
from app.config import settings
from app.telegram_sender import build_telegram_payload, send_to_telegram


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
        """推送内容到 Telegram 频道/群组"""
        try:
            bot = await self._get_bot()
            text, media_items = build_telegram_payload(content)
            message_id = await send_to_telegram(bot, target_id, text, media_items)
            
            if message_id:
                logger.info(f"成功推送到 Telegram: target_id={target_id}, message_id={message_id}")
            else:
                logger.error(f"推送失败，未获取到消息ID: target_id={target_id}")
            
            return message_id
        except Exception as e:
            logger.exception(f"推送失败: {e}")
            return None


# 全局单例
_push_service: Optional[PushService] = None


def get_push_service() -> PushService:
    """获取推送服务单例"""
    global _push_service
    if _push_service is None:
        _push_service = PushService()
    return _push_service
