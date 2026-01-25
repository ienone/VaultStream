"""
Bot 主程序模块

负责 Bot 应用的初始化、配置和启动
"""
import httpx
from telegram import BotCommand, Update
from telegram.ext import (
    Application,
    CommandHandler,
    CallbackQueryHandler,
)
from app.core.logging import logger
from app.core.config import settings

from .permissions import PermissionManager
from .commands import (
    start_command, help_command, status_command,
    get_command, get_tag_command, get_twitter_command, get_bilibili_command, list_tags_command
)
from .callbacks import button_callback


class VaultStreamBot:
    """VaultStream Telegram Bot"""
    
    def __init__(self):
        self.api_base = f"http://localhost:{settings.api_port}/api/v1"
        self.target_platform = f"TG_CHANNEL_{settings.telegram_channel_id}"
        
        # 解析权限配置
        self.admin_ids = self._parse_ids(settings.telegram_admin_ids)
        self.whitelist_ids = self._parse_ids(settings.telegram_whitelist_ids)
        self.blacklist_ids = self._parse_ids(settings.telegram_blacklist_ids)
        
        self.permission_manager = PermissionManager(
            self.admin_ids, self.whitelist_ids, self.blacklist_ids
        )
        
        logger.info(f"Bot 权限配置: admins={len(self.admin_ids)}, whitelist={len(self.whitelist_ids)}, blacklist={len(self.blacklist_ids)}")

    def _parse_ids(self, ids_str: str) -> set:
        """解析ID列表字符串"""
        if not ids_str or not ids_str.strip():
            return set()
        return {int(id.strip()) for id in ids_str.split(",") if id.strip()}

    async def post_init(self, application: Application) -> None:
        """应用启动后的初始化回调"""
        try:
            # 注入依赖到 bot_data
            application.bot_data["permission_manager"] = self.permission_manager
            application.bot_data["api_base"] = self.api_base
            application.bot_data["target_platform"] = self.target_platform
            application.bot_data["channel_id"] = settings.telegram_channel_id
            
            # 创建并注入 http_client
            client = httpx.AsyncClient(timeout=30.0)
            application.bot_data["http_client"] = client
            
            logger.info("正在验证 Telegram Bot 连接...")
            bot_info = await application.bot.get_me()
            logger.info(f"Bot 连接成功: @{bot_info.username} (ID: {bot_info.id})")
            
            # 设置命令菜单
            commands = [
                BotCommand("get", "随机获取一条内容"),
                BotCommand("get_tag", "按标签获取内容"),
                BotCommand("get_twitter", "获取 Twitter 推文"),
                BotCommand("get_bilibili", "获取 B站内容"),
                BotCommand("list_tags", "查看所有标签"),
                BotCommand("status", "查看系统状态"),
                BotCommand("help", "显示帮助信息"),
            ]
            await application.bot.set_my_commands(commands)
            
            # 验证频道访问权限
            try:
                chat = await application.bot.get_chat(settings.telegram_channel_id)
                logger.info(f"频道访问验证成功: {chat.title or chat.username}")
            except Exception as e:
                logger.error(f"无法访问频道 {settings.telegram_channel_id}: {e}")
                
            # 验证后端API连接
            try:
                response = await client.get(f"{self.api_base}/health", timeout=5.0)
                if response.status_code == 200:
                    logger.info("后端API连接成功")
                else:
                    logger.warning(f"后端API响应异常: {response.status_code}")
            except Exception as e:
                logger.error(f"无法连接到后端API: {e}")
                
            logger.info("Bot 已就绪，开始监听消息...")
            
        except Exception as e:
            logger.error(f"Bot 初始化失败: {e}")
            raise

    async def post_shutdown(self, application: Application) -> None:
        """应用关闭后的清理回调"""
        logger.info("正在清理资源...")
        client: httpx.AsyncClient = application.bot_data.get("http_client")
        if client:
            await client.aclose()
        logger.info("资源清理完成")

    def run(self):
        """运行Bot"""
        if not settings.telegram_bot_token or not settings.telegram_bot_token.get_secret_value():
            logger.error("未配置 TELEGRAM_BOT_TOKEN")
            return
        
        logger.info("正在启动 Telegram Bot...")
        
        # 创建应用构建器
        builder = Application.builder().token(settings.telegram_bot_token.get_secret_value())
        
        # 配置代理
        if hasattr(settings, 'http_proxy') and settings.http_proxy:
            logger.info(f"使用HTTP代理: {settings.http_proxy}")
            builder.proxy(settings.http_proxy)
            builder.get_updates_proxy(settings.http_proxy)
            
        builder.connect_timeout(10)
        builder.read_timeout(10)
        
        # 设置回调
        builder.post_init(self.post_init)
        builder.post_shutdown(self.post_shutdown)
        
        application = builder.build()
        
        # 注册处理器
        application.add_handler(CommandHandler("start", start_command))
        application.add_handler(CommandHandler("help", help_command))
        application.add_handler(CommandHandler("get", get_command))
        application.add_handler(CommandHandler("get_tag", get_tag_command))
        application.add_handler(CommandHandler("get_twitter", get_twitter_command))
        application.add_handler(CommandHandler("get_bilibili", get_bilibili_command))
        application.add_handler(CommandHandler("list_tags", list_tags_command))
        application.add_handler(CommandHandler("status", status_command))
        
        application.add_handler(CallbackQueryHandler(button_callback))
        
        try:
            application.run_polling(
                allowed_updates=Update.ALL_TYPES,
                drop_pending_updates=True,
                close_loop=False
            )
        except KeyboardInterrupt:
            logger.info("Bot 已停止")
        except Exception as e:
            logger.exception(f"Bot 运行出错: {e}")

if __name__ == "__main__":
    bot = VaultStreamBot()
    bot.run()
