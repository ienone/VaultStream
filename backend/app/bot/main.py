"""
Bot 主程序模块

负责 Bot 应用的初始化、配置和启动
"""
import httpx
from telegram import BotCommand, Update, ChatMemberUpdated
from telegram.ext import (
    Application,
    CommandHandler,
    CallbackQueryHandler,
    ChatMemberHandler,
)
from app.core.logging import logger
from app.core.config import settings

from .permissions import PermissionManager
from .commands import (
    start_command, help_command, status_command,
    get_command, get_tag_command, get_twitter_command, get_bilibili_command, list_tags_command
)
from .callbacks import button_callback

BOT_VERSION = "0.2.0"


class VaultStreamBot:
    """VaultStream Telegram Bot"""
    
    def __init__(self):
        self.api_base = f"http://localhost:{settings.api_port}/api/v1"
        self.target_platform = f"TG_CHANNEL_{settings.telegram_channel_id}"
        self.api_token = settings.api_token.get_secret_value() if settings.api_token else ""
        
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

    def _get_headers(self) -> dict:
        """获取 API 请求头"""
        headers = {"Content-Type": "application/json"}
        if self.api_token:
            headers["X-API-Token"] = self.api_token
        return headers

    async def _send_heartbeat(self, context) -> None:
        """发送心跳到后端 API"""
        try:
            bot_info = await context.bot.get_me()
            client: httpx.AsyncClient = context.bot_data.get("http_client")
            if not client:
                return
            
            payload = {
                "bot_id": str(bot_info.id),
                "bot_username": bot_info.username,
                "bot_first_name": bot_info.first_name,
                "version": BOT_VERSION,
            }
            
            response = await client.post(
                f"{self.api_base}/bot/heartbeat",
                json=payload,
                headers=self._get_headers(),
                timeout=10.0,
            )
            if response.status_code != 200:
                logger.warning(f"心跳上报失败: {response.status_code}")
        except Exception as e:
            logger.warning(f"心跳上报异常: {e}")

    async def _upsert_chat(self, client: httpx.AsyncClient, chat, bot) -> None:
        """上报群组/频道信息到后端"""
        try:
            # 获取 Bot 在该群组的权限
            is_admin = False
            can_post = False
            try:
                bot_member = await bot.get_chat_member(chat.id, (await bot.get_me()).id)
                is_admin = bot_member.status in ['administrator', 'creator']
                can_post = getattr(bot_member, 'can_post_messages', True) if is_admin else False
            except:
                pass
            
            # 获取成员数
            member_count = None
            try:
                member_count = await bot.get_chat_member_count(chat.id)
            except:
                pass
            
            payload = {
                "chat_id": str(chat.id),
                "chat_type": chat.type,
                "title": chat.title,
                "username": chat.username,
                "description": chat.description,
                "member_count": member_count,
                "is_admin": is_admin,
                "can_post": can_post,
            }
            
            response = await client.put(
                f"{self.api_base}/bot/chats:upsert",
                json=payload,
                headers=self._get_headers(),
                timeout=10.0,
            )
            if response.status_code == 200:
                logger.info(f"群组已上报: {chat.title or chat.id}")
            else:
                logger.warning(f"群组上报失败: {response.status_code} - {response.text}")
        except Exception as e:
            logger.error(f"群组上报异常: {e}")

    async def post_init(self, application: Application) -> None:
        """应用启动后的初始化回调"""
        try:
            # 注入依赖到 bot_data
            application.bot_data["permission_manager"] = self.permission_manager
            application.bot_data["api_base"] = self.api_base
            application.bot_data["target_platform"] = self.target_platform
            application.bot_data["channel_id"] = settings.telegram_channel_id
            application.bot_data["bot_instance"] = self
            
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
            
            # 验证频道访问权限并上报
            try:
                chat = await application.bot.get_chat(settings.telegram_channel_id)
                logger.info(f"频道访问验证成功: {chat.title or chat.username}")
                # 上报频道信息
                await self._upsert_chat(client, chat, application.bot)
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
            
            # 发送初始心跳
            await self._send_heartbeat(application)
            
            # 设置定时心跳任务（每 30 秒）
            application.job_queue.run_repeating(
                self._send_heartbeat,
                interval=30,
                first=30,
                name="heartbeat",
            )
                
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
        
        # 注册群组成员变更处理器（用于自动发现群组）
        application.add_handler(ChatMemberHandler(
            _handle_my_chat_member,
            ChatMemberHandler.MY_CHAT_MEMBER
        ))
        
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


async def _handle_my_chat_member(update: Update, context) -> None:
    """处理 Bot 自身的成员状态变更（加入/离开群组）"""
    if not update.my_chat_member:
        return
    
    chat_member: ChatMemberUpdated = update.my_chat_member
    chat = chat_member.chat
    new_status = chat_member.new_chat_member.status
    old_status = chat_member.old_chat_member.status
    
    logger.info(f"Bot 成员状态变更: {chat.title or chat.id} | {old_status} -> {new_status}")
    
    bot_instance: VaultStreamBot = context.bot_data.get("bot_instance")
    client: httpx.AsyncClient = context.bot_data.get("http_client")
    
    if not bot_instance or not client:
        return
    
    # Bot 加入或权限变更
    if new_status in ['member', 'administrator', 'creator']:
        await bot_instance._upsert_chat(client, chat, context.bot)
    # Bot 被踢出或离开
    elif new_status in ['left', 'kicked']:
        logger.info(f"Bot 已离开群组: {chat.title or chat.id}")


if __name__ == "__main__":
    bot = VaultStreamBot()
    bot.run()
