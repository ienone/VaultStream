"""
Telegram Bot - 改进版
"""
import asyncio
import httpx
from typing import Optional, List, Dict, Any
from telegram import Update, BotCommand, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application,
    CommandHandler,
    CallbackQueryHandler,
    ContextTypes,
)
from app.logging import logger

from app.config import settings
from app.utils import normalize_bilibili_url
from app.telegram_sender import build_telegram_payload, send_to_telegram


class VaultStreamBot:
    """VaultStream Telegram Bot"""
    
    def __init__(self):
        self.api_base = f"http://localhost:{settings.api_port}/api/v1"
        self.target_platform = f"TG_CHANNEL_{settings.telegram_channel_id}"
        self._client: Optional[httpx.AsyncClient] = None
        
        # 解析权限配置
        self.admin_ids = self._parse_ids(settings.telegram_admin_ids)
        self.whitelist_ids = self._parse_ids(settings.telegram_whitelist_ids)
        self.blacklist_ids = self._parse_ids(settings.telegram_blacklist_ids)
        
        logger.info(f"Bot 权限配置: admins={len(self.admin_ids)}, whitelist={len(self.whitelist_ids)}, blacklist={len(self.blacklist_ids)}")
    
    def _parse_ids(self, ids_str: str) -> set:
        """解析ID列表字符串"""
        if not ids_str or not ids_str.strip():
            return set()
        return {int(id.strip()) for id in ids_str.split(",") if id.strip()}
    
    def _check_permission(self, user_id: int, require_admin: bool = False) -> tuple[bool, Optional[str]]:
        """
        检查用户权限
        
        Args:
            user_id: 用户ID
            require_admin: 是否需要管理员权限
        
        Returns:
            (是否允许, 拒绝原因)
        """
        # 检查黑名单
        if user_id in self.blacklist_ids:
            return False, "您已被禁止使用此Bot"
        
        # 检查管理员权限
        if require_admin:
            if user_id not in self.admin_ids:
                return False, "此命令仅限管理员使用"
            return True, None
        
        # 检查白名单（如果配置了白名单）
        if self.whitelist_ids:
            if user_id not in self.whitelist_ids and user_id not in self.admin_ids:
                return False, "您没有权限使用此Bot"
        
        return True, None
    
    async def _get_client(self) -> httpx.AsyncClient:
        """获取或创建复用的 httpx 客户端"""
        if self._client is None or self._client.is_closed:
            self._client = httpx.AsyncClient(timeout=30.0)
        return self._client
    
    async def close(self):
        """关闭客户端连接"""
        if self._client and not self._client.is_closed:
            await self._client.aclose()
    
    async def start_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """处理 /start 命令"""
        user = update.effective_user
        logger.info(f"Bot /start 命令: user={user.username}(ID:{user.id})")
        
        # 权限检查
        allowed, reason = self._check_permission(user.id)
        if not allowed:
            await update.message.reply_text(reason)
            return
        
        help_text = (
            "欢迎使用 <b>VaultStream Bot</b>\n\n"
            "<b>可用命令</b>:\n"
            "/get - 随机获取一条待推送的内容\n"
            "/get_tag &lt;标签&gt; - 获取指定标签的内容\n"
            "/get_twitter - 获取 Twitter 推文\n"
            "/get_bilibili - 获取 B站内容\n"
            "/list_tags - 查看所有可用标签\n"
            "/status - 查看系统状态\n"
            "/help - 显示详细帮助\n\n"
            "<b>示例</b>:\n"
            "<code>/get_tag 技术</code>\n"
            "<code>/get_twitter</code>\n"
        )
        
        await update.message.reply_text(help_text, parse_mode='HTML')
        logger.info("Bot /start 响应已发送")
    
    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """处理 /help 命令"""
        user = update.effective_user
        logger.info(f"Bot /help 命令: user={user.username}(ID:{user.id})")
        
        # 权限检查
        allowed, reason = self._check_permission(user.id)
        if not allowed:
            await update.message.reply_text(reason)
            return
        
        # 权限检查
        allowed, reason = self._check_permission(user.id)
        if not allowed:
            await update.message.reply_text(reason)
            return
        
        help_text = (
            "<b>VaultStream Bot 帮助</b>\n\n"
            
            "<b>基本命令</b>\n"
            "/get - 随机获取一条待推送的内容\n"
            "/status - 查看系统运行状态和队列情况\n\n"
            
            "<b>按标签筛选</b>\n"
            "/get_tag &lt;标签&gt; - 获取带指定标签的内容\n"
            "/list_tags - 查看所有可用标签及其数量\n"
            "示例: <code>/get_tag 技术</code>\n\n"
            
            "<b>按平台筛选</b>\n"
            "/get_twitter - 获取 Twitter/X 平台的推文\n"
            "/get_bilibili - 获取 B站平台的内容\n\n"
            
            "<b>使用说明</b>\n"
            "• 所有命令都会自动标记为已推送\n"
            "• 可以组合使用标签和平台筛选\n"
            "• 内容按创建时间顺序获取\n"
        )
        await update.message.reply_text(help_text, parse_mode='HTML')
    
    async def get_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """处理 /get 命令"""
        user = update.effective_user if update and update.effective_user else None
        logger.info(f"Bot /get 命令触发: user={user.username if user and user.username else 'unknown'}(ID:{user.id if user else 'unknown'})")
        
        if not update or not update.message:
            logger.warning("Bot /get 命令: update 或 message 为空")
            return
        
        # 权限检查
        allowed, reason = self._check_permission(user.id)
        if not allowed:
            await update.message.reply_text(reason)
            return
        
        # 权限检查
        allowed, reason = self._check_permission(user.id)
        if not allowed:
            await update.message.reply_text(reason)
            return
        
        # 兼容旧用法: /get 标签
        tag = None
        if context.args and len(context.args) > 0:
            tag = context.args[0].strip() if context.args[0].strip() else None
        
        await self._get_content_by_filter(update, context, tag=tag)
    
    async def get_tag_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """处理 /get_tag 命令"""
        user = update.effective_user if update and update.effective_user else None
        logger.info(f"Bot /get_tag 命令触发: user={user.username if user and user.username else 'unknown'}(ID:{user.id if user else 'unknown'})")
        
        if not update or not update.message:
            logger.warning("Bot /get_tag 命令: update 或 message 为空")
            return
        
        # 权限检查
        allowed, reason = self._check_permission(user.id)
        if not allowed:
            await update.message.reply_text(reason)
            return
        
        if not context.args or len(context.args) == 0:
            await update.message.reply_text(
                "请指定标签\n\n"
                "用法: <code>/get_tag 标签名</code>\n"
                "示例: <code>/get_tag 技术</code>",
                parse_mode='HTML'
            )
            return
        
        tag = context.args[0].strip()
        await self._get_content_by_filter(update, context, tag=tag)
    
    async def get_twitter_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """处理 /get_twitter 命令"""
        user = update.effective_user if update and update.effective_user else None
        logger.info(f"Bot /get_twitter 命令触发: user={user.username if user and user.username else 'unknown'}(ID:{user.id if user else 'unknown'})")
        
        if not update or not update.message:
            logger.warning("Bot /get_twitter 命令: update 或 message 为空")
            return
        await self._get_content_by_filter(update, context, platform="twitter")
    
    async def get_bilibili_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """处理 /get_bilibili 命令"""
        user = update.effective_user if update and update.effective_user else None
        logger.info(f"Bot /get_bilibili 命令触发: user={user.username if user and user.username else 'unknown'}(ID:{user.id if user else 'unknown'})")
        
        if not update or not update.message:
            logger.warning("Bot /get_bilibili 命令: update 或 message 为空")
            return
        await self._get_content_by_filter(update, context, platform="bilibili")
    
    async def list_tags_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """处理 /list_tags 命令"""
        user = update.effective_user if update and update.effective_user else None
        logger.info(f"Bot /list_tags 命令触发: user={user.username if user and user.username else 'unknown'}(ID:{user.id if user else 'unknown'})")
        
        if not update or not update.message:
            logger.warning("Bot /list_tags 命令: update 或 message 为空")
            return
        
        try:
            client = await self._get_client()
            response = await client.get(f"{self.api_base}/tags", timeout=5.0)
            
            if response.status_code != 200:
                await update.message.reply_text("无法获取标签列表")
                return
            
            tags_data = response.json()
            
            if not tags_data or len(tags_data) == 0:
                await update.message.reply_text("暂无任何标签")
                return
            
            # API 返回格式: [{"name": "tag1", "count": 10}, ...]
            # 已按 count 降序排序
            tag_lines = []
            for tag_item in tags_data[:20]:
                tag_lines.append(f"• {tag_item['name']}: {tag_item['count']}")
            
            message = "<b>可用标签</b>\n\n" + "\n".join(tag_lines)
            
            if len(tags_data) > 20:
                message += f"\n\n还有 {len(tags_data) - 20} 个标签"
            
            await update.message.reply_text(message, parse_mode='HTML')
            
        except Exception as e:
            logger.exception("/list_tags 命令失败")
            await update.message.reply_text("获取标签列表失败")
    
    async def status_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """处理 /status 命令"""
        import time
        start_time = time.time()
        
        if not update or not update.message:
            return
        
        user = update.effective_user
        logger.info(f"Bot /status 命令: user={user.username}(ID:{user.id})")
            
        try:
            client = await self._get_client()
            
            try:
                api_start = time.time()
                response = await client.get(f"{self.api_base}/health", timeout=5.0)
                api_time = time.time() - api_start
                logger.info(f"Health API请求耗时: {api_time:.3f}秒")
            except httpx.TimeoutException:
                await update.message.reply_text("请求超时")
                return
            except httpx.RequestError as e:
                logger.error(f"健康检查请求错误: {e}")
                await update.message.reply_text("无法连接到后端服务")
                return
            
            if response.status_code != 200:
                await update.message.reply_text(f"服务异常 (状态码: {response.status_code})")
                return
                
            data = response.json()
            status = data.get('status', 'unknown')
            queue_size = data.get('queue_size', '?')
            
            status_icon = "✓" if status == "ok" else "✗"
            
            send_start = time.time()
            await update.message.reply_text(
                f"<b>系统状态</b>\n\n"
                f"{status_icon} 状态: {status}\n"
                f"队列任务数: {queue_size}",
                parse_mode='HTML'
            )
            send_time = time.time() - send_start
            total_time = time.time() - start_time
            logger.info(f"Bot /status 响应已发送: status={status}, queue_size={queue_size}, Telegram发送耗时={send_time:.3f}秒, 总耗时={total_time:.3f}秒")
        except Exception as e:
            logger.exception("处理 /status 命令失败")
            try:
                await update.message.reply_text("获取状态失败")
            except Exception:
                pass
    
    async def button_callback(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """处理按钮回调"""
        query = update.callback_query
        await query.answer()
        
        user = update.effective_user
        callback_data = query.data
        
        logger.info(f"Bot 按钮回调: user={user.username}(ID:{user.id}), data={callback_data}")
        
        # 按钮操作需要管理员权限
        allowed, reason = self._check_permission(user.id, require_admin=True)
        if not allowed:
            try:
                await query.edit_message_text(reason)
            except Exception:
                pass  # 忽略消息未修改的错误
            return
        
        try:
            # 解析回调数据: action_contentid
            parts = callback_data.split("_", 1)
            if len(parts) != 2:
                await query.edit_message_text("无效的操作")
                return
            
            action, content_id = parts
            content_id = int(content_id)
            
            client = await self._get_client()
            
            if action == "delete":
                # 删除内容
                try:
                    response = await client.delete(
                        f"{self.api_base}/contents/{content_id}",
                        timeout=5.0
                    )
                    if response.status_code == 200:
                        try:
                            await query.edit_message_text(
                                f"✓ 内容 {content_id} 已删除",
                                reply_markup=None
                            )
                        except Exception:
                            pass
                        # 尝试删除原消息
                        try:
                            if query.message and query.message.reply_to_message:
                                await query.message.reply_to_message.delete()
                        except Exception:
                            pass
                    else:
                        try:
                            await query.edit_message_text(f"删除失败: {response.status_code}")
                        except Exception:
                            pass
                except Exception as e:
                    logger.error(f"删除内容失败: {e}")
                    try:
                        await query.edit_message_text(f"操作失败: {str(e)[:100]}")
                    except Exception:
                        pass
            
            else:
                try:
                    await query.edit_message_text(f"未知操作: {action}")
                except Exception:
                    pass
                
        except ValueError:
            try:
                await query.edit_message_text("无效的内容ID")
            except Exception:
                pass
        except Exception as e:
            logger.exception(f"处理按钮回调失败: {e}")
            await query.edit_message_text(f"操作失败: {str(e)[:100]}")
    
    async def _get_content_by_filter(
        self, 
        update: Update, 
        context: ContextTypes.DEFAULT_TYPE,
        tag: Optional[str] = None,
        platform: Optional[str] = None
    ):
        """通用的内容获取方法"""
        import time
        start_time = time.time()
        
        try:
            user = update.effective_user
            filter_desc = []
            if tag:
                filter_desc.append(f"标签={tag}")
            if platform:
                filter_desc.append(f"平台={platform}")
            
            logger.info(f"Bot 获取内容: user={user.username}(ID:{user.id}), {', '.join(filter_desc) if filter_desc else '无筛选'}")
            
            # 构建请求
            client = await self._get_client()
            payload = {
                "target_platform": self.target_platform,
                "limit": 1
            }
            if tag:
                payload["tag"] = tag
            if platform:
                payload["platform"] = platform
            
            try:
                api_start = time.time()
                response = await client.post(
                    f"{self.api_base}/bot/get-content",
                    json=payload,
                    timeout=10.0
                )
                api_time = time.time() - api_start
                logger.info(f"API请求耗时: {api_time:.3f}秒")
            except httpx.TimeoutException:
                await update.message.reply_text("请求超时，请稍后重试")
                return
            except httpx.RequestError:
                await update.message.reply_text("无法连接到后端服务")
                return
            
            if response.status_code != 200:
                try:
                    error_detail = response.json().get('detail', '未知错误')
                except:
                    error_detail = '未知错误'
                await update.message.reply_text(f"获取内容失败: {error_detail}")
                return
            
            contents = response.json()
            
            if not contents or len(contents) == 0:
                filter_msg = f" ({', '.join(filter_desc)})" if filter_desc else ""
                await update.message.reply_text(f"暂无符合条件的内容{filter_msg}")
                return
            
            content = contents[0]
            content_id = content.get("id")
            
            if not content_id:
                await update.message.reply_text("内容数据异常")
                return
            
            # 发送到频道
            send_start = time.time()
            await self.send_content_to_channel(content, context)
            send_time = time.time() - send_start
            logger.info(f"Bot 成功发送内容到频道: content_id={content_id}, platform={content.get('platform')}, 发送耗时={send_time:.3f}秒")
            
            # 异步标记为已推送
            asyncio.create_task(self._mark_pushed_async(content_id))
            
            title = content.get('title') or content.get('url', '未知内容')
            title_short = title[:50] + "..." if len(title) > 50 else title
            
            platform_name = {"twitter": "Twitter", "bilibili": "B站"}.get(content.get('platform'), content.get('platform', ''))
            await update.message.reply_text(f"已发送: {title_short}\n平台: {platform_name}")
            total_time = time.time() - start_time
            logger.info(f"Bot 响应用户成功: title={title_short}, platform={platform_name}, 总耗时={total_time:.3f}秒")
            
        except Exception as e:
            logger.exception("获取内容失败")
            await update.message.reply_text(f"发送失败: {str(e)[:100]}")
    
    async def _mark_pushed_async(self, content_id: int):
        """异步标记内容为已推送"""
        try:
            client = await self._get_client()
            await client.post(
                f"{self.api_base}/bot/mark-pushed",
                json={
                    "content_id": content_id,
                    "target_platform": self.target_platform,
                    "target_id": str(settings.telegram_channel_id)  # 添加缺失的 target_id
                }
            )
        except Exception as e:
            logger.warning(f"标记已推送失败: content_id={content_id}, error={e}")
    
    async def send_content_to_channel(self, content: dict, context: ContextTypes.DEFAULT_TYPE):
        """发送内容到频道"""
        import time
        
        if not content:
            raise ValueError("内容为空")
            
        content_id = content.get("id")
        
        try:
            format_start = time.time()
            text, media_items = build_telegram_payload(content)
            format_time = time.time() - format_start
            logger.debug(f"格式化文本耗时: {format_time:.3f}秒")
            
            # 创建 InlineKeyboard 按钮（仅保留删除功能）
            keyboard = [
                [
                    InlineKeyboardButton("🗑️ 删除", callback_data=f"delete_{content_id}"),
                ]
            ]
            reply_markup = InlineKeyboardMarkup(keyboard)
            
            await send_to_telegram(
                context.bot,
                settings.telegram_channel_id,
                text,
                media_items,
                reply_markup=reply_markup
            )
        except Exception as e:
            logger.exception("发送到频道失败")
            raise

    async def post_init(self, application: Application) -> None:
        """应用启动后的初始化回调"""
        try:
            logger.info("正在验证 Telegram Bot 连接...")
            
            # 获取Bot信息
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
            logger.info("命令菜单已设置")
            
            # 验证频道访问权限
            try:
                chat = await application.bot.get_chat(settings.telegram_channel_id)
                logger.info(f"频道访问验证成功: {chat.title or chat.username or settings.telegram_channel_id}")
            except Exception as e:
                logger.error(f"无法访问频道 {settings.telegram_channel_id}: {e}")
                logger.error("请检查: 1) 频道ID是否正确  2) Bot是否已添加为频道管理员")
                raise
            
            # 验证后端API连接
            try:
                client = await self._get_client()
                response = await client.get(f"{self.api_base}/health", timeout=5.0)
                if response.status_code == 200:
                    logger.info(f"后端API连接成功: {self.api_base}")
                else:
                    logger.warning(f"后端API响应异常 (状态码: {response.status_code})")
            except Exception as e:
                logger.error(f"无法连接到后端API {self.api_base}: {e}")
                logger.error("请确保后端服务已启动")
                raise
            
            logger.info("=" * 60)
            logger.info("Bot 已就绪，开始监听消息...")
            logger.info("按 Ctrl+C 停止")
            logger.info("=" * 60)
            
        except Exception as e:
            logger.error(f"Bot 初始化失败: {e}")
            raise
    
    async def post_shutdown(self, application: Application) -> None:
        """应用关闭后的清理回调"""
        logger.info("正在清理资源...")
        await self.close()
        logger.info("资源清理完成")
    
    def run(self):
        """运行Bot - 使用现代化的 API"""
        if not settings.telegram_bot_token or not settings.telegram_bot_token.get_secret_value():
            logger.error("未配置 TELEGRAM_BOT_TOKEN")
            return
        
        if not settings.telegram_channel_id:
            logger.error("未配置 TELEGRAM_CHANNEL_ID")
            return
        
        logger.info("=" * 60)
        logger.info("正在启动 Telegram Bot...")
        logger.info("=" * 60)
        
        # 创建应用构建器
        builder = Application.builder().token(settings.telegram_bot_token.get_secret_value())
        
        # 配置代理
        if hasattr(settings, 'http_proxy') and settings.http_proxy:
            logger.info(f"Telegram Bot使用HTTP代理: {settings.http_proxy}")
            builder.proxy(settings.http_proxy)
            builder.get_updates_proxy(settings.http_proxy)
        else:
            logger.info("未配置代理，直接连接")
        
        # 设置超时
        builder.connect_timeout(10)
        builder.read_timeout(10)
        
        # 设置初始化和关闭回调
        builder.post_init(self.post_init)
        builder.post_shutdown(self.post_shutdown)
        
        application = builder.build()
        
        # 注册命令处理器
        logger.info("注册命令处理器...")
        application.add_handler(CommandHandler("start", self.start_command))
        application.add_handler(CommandHandler("help", self.help_command))
        application.add_handler(CommandHandler("get", self.get_command))
        application.add_handler(CommandHandler("get_tag", self.get_tag_command))
        application.add_handler(CommandHandler("get_twitter", self.get_twitter_command))
        application.add_handler(CommandHandler("get_bilibili", self.get_bilibili_command))
        application.add_handler(CommandHandler("list_tags", self.list_tags_command))
        application.add_handler(CommandHandler("status", self.status_command))
        
        # 注册按钮回调处理器
        application.add_handler(CallbackQueryHandler(self.button_callback))
        
        logger.info("已注册 8 个命令处理器 + 1 个回调处理器")
        
        # 启动轮询 - 使用简洁的现代 API
        try:
            application.run_polling(
                allowed_updates=Update.ALL_TYPES,
                drop_pending_updates=True,
                close_loop=False
            )
        except KeyboardInterrupt:
            logger.info("\nBot 已停止")
        except Exception as e:
            logger.exception(f"Bot 运行出错: {e}")


if __name__ == "__main__":
    bot = VaultStreamBot()
    bot.run()
