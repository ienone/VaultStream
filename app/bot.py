"""
Telegram Bot
"""
import asyncio
import httpx
from telegram import Update
from telegram.ext import (
    Application,
    CommandHandler,
    ContextTypes,
)
from loguru import logger

from app.config import settings
from app.utils import normalize_bilibili_url, format_content_for_tg


class VaultStreamBot:
    """VaultStream Telegram Bot"""
    
    def __init__(self):
        self.api_base = f"http://localhost:{settings.api_port}/api/v1"
        self.target_platform = f"TG_CHANNEL_{settings.telegram_channel_id}"
        
    async def start_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """处理 /start 命令"""
        await update.message.reply_text(
            "欢迎使用 VaultStream Bot!\n\n"
            "可用命令:\n"
            "/get [tag] - 获取并发送一条内容\n"
            "/status - 查看系统状态"
        )
    
    async def get_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """处理 /get 命令 - 获取并发送内容"""
        try:
            # 解析参数
            tag = context.args[0] if context.args else None
            
            # 调试日志：记录请求参数
            logger.debug(f"请求后端 API: {self.api_base}/bot/get-content, platform: {self.target_platform}, tag: {tag}")
            
            # 从后端获取内容
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    f"{self.api_base}/bot/get-content",
                    json={
                        "target_platform": self.target_platform,
                        "tag": tag,
                        "limit": 1
                    }
                )
                
                # 调试日志：记录响应状态
                logger.debug(f"后端 API 响应状态码: {response.status_code}")
                
                if response.status_code != 200:
                    logger.error(f"后端 API 错误详情: {response.text}")
                    await update.message.reply_text("获取内容失败")
                    return
                
                contents = response.json()
                
                # 调试日志：记录返回的数据内容
                logger.debug(f"后端 API 返回内容数量: {len(contents)}")
                if contents:
                    logger.debug(f"首条内容详情: ID={contents[0].get('id')}, Status={contents[0].get('status')}, Title={contents[0].get('title')}, ContentType={contents[0].get('content_type')}")
                
                if not contents:
                    await update.message.reply_text("暂无待推送的内容")
                    return
                
                content = contents[0]
                
                # 发送到频道
                await self.send_content_to_channel(content, context)
                
                # 标记为已推送
                await client.post(
                    f"{self.api_base}/bot/mark-pushed",
                    json={
                        "content_id": content["id"],
                        "target_platform": self.target_platform
                    }
                )
                
                await update.message.reply_text(
                    f"✅ 已发送: {content['title'] or content['url']}"
                )
                
        except Exception as e:
            logger.error(f"处理 /get 命令失败: {e}")
            await update.message.reply_text(f"发送失败: {str(e)}")
    
    async def status_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """处理 /status 命令 - 查看系统状态"""
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(f"{self.api_base}/health")
                data = response.json()
                
                await update.message.reply_text(
                    f"📊 系统状态\n\n"
                    f"状态: {data['status']}\n"
                    f"队列任务数: {data['queue_size']}"
                )
        except Exception as e:
            logger.error(f"处理 /status 命令失败: {e}")
            await update.message.reply_text("获取状态失败")

    async def send_content_to_channel(self, content: dict, context: ContextTypes.DEFAULT_TYPE):
        """发送内容到频道"""
        try:
            text = format_content_for_tg(content)
            
            if content.get('cover_url'):
                await context.bot.send_photo(
                    chat_id=settings.telegram_channel_id,
                    photo=content['cover_url'],
                    caption=text,
                    parse_mode='HTML'
                )
            else:
                await context.bot.send_message(
                    chat_id=settings.telegram_channel_id,
                    text=text,
                    parse_mode='HTML',
                    disable_web_page_preview=False
                )
        except Exception as e:
            logger.error(f"发送到频道失败: {e}")
            raise

    def run(self):
        """运行Bot"""
        if not settings.telegram_bot_token:
            logger.error("未配置 TELEGRAM_BOT_TOKEN")
            return
        
        if not settings.telegram_channel_id:
            logger.error("未配置 TELEGRAM_CHANNEL_ID")
            return
        
        # 创建应用
        builder = Application.builder().token(settings.telegram_bot_token)
        
        # 配置代理
        if hasattr(settings, 'telegram_proxy_url') and settings.telegram_proxy_url:
            logger.info(f"使用代理: {settings.telegram_proxy_url}")
            builder.proxy(settings.telegram_proxy_url)
            builder.get_updates_proxy(settings.telegram_proxy_url)
            builder.connect_timeout(10)
            builder.read_timeout(10)
            
        application = builder.build()
        
        # 注册命令处理器
        application.add_handler(CommandHandler("start", self.start_command))
        application.add_handler(CommandHandler("get", self.get_command))
        application.add_handler(CommandHandler("status", self.status_command))
        
        # 启动Bot
        logger.info("Telegram Bot starting...")
        application.run_polling(
            allowed_updates=Update.ALL_TYPES,
            drop_pending_updates=True
            )


if __name__ == "__main__":
    bot = VaultStreamBot()
    bot.run()
