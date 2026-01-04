"""
Telegram Bot
"""
import asyncio
import httpx
from typing import Optional
from telegram import Update
from telegram.ext import (
    Application,
    CommandHandler,
    ContextTypes,
)
from app.logging import logger

from app.config import settings
from app.utils import normalize_bilibili_url, format_content_for_tg


class VaultStreamBot:
    """VaultStream Telegram Bot"""
    
    def __init__(self):
        self.api_base = f"http://localhost:{settings.api_port}/api/v1"
        self.target_platform = f"TG_CHANNEL_{settings.telegram_channel_id}"
        # 复用 httpx 客户端，避免重复建立连接
        self._client: Optional[httpx.AsyncClient] = None
    
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
        logger.info(f"Bot /start 命令: user={user.username or user.id}")
        
        await update.message.reply_text(
            "欢迎使用 VaultStream Bot!\n\n"
            "可用命令:\n"
            "/get [tag] - 获取并发送一条内容\n"
            "/status - 查看系统状态"
        )
        logger.info(f"Bot /start 响应已发送")
    
    async def get_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """处理 /get 命令 - 获取并发送内容
        
        用法:
            /get           - 获取任意一条待推送内容
            /get tag1      - 获取带指定标签的内容
        """
        # 安全处理，避免update或message为None
        if not update or not update.message:
            logger.warning("收到无效的update对象")
            return
        
        try:
            # 解析参数，支持多种格式
            tag = None
            if context.args and len(context.args) > 0:
                # 去除首尾空格，忽略空字符串
                tag = context.args[0].strip() if context.args[0].strip() else None
            
            user = update.effective_user
            logger.info(f"Bot /get 命令: user={user.username or user.id}, tag={tag}")
            
            # 从后端获取内容
            client = await self._get_client()
            
            try:
                response = await client.post(
                    f"{self.api_base}/bot/get-content",
                    json={
                        "target_platform": self.target_platform,
                        "tag": tag,
                        "limit": 1
                    },
                    timeout=10.0  # 设置超时
                )
            except httpx.TimeoutException:
                logger.error("后端 API 请求超时")
                await update.message.reply_text("⏱️ 请求超时，请稍后重试")
                return
            except httpx.RequestError as e:
                logger.error(f"后端 API 请求错误: {e}")
                await update.message.reply_text("❌ 无法连接到后端服务")
                return
            
            if response.status_code != 200:
                logger.error(f"后端 API 错误: status={response.status_code}")
                try:
                    # response.json() 在无法解析时会抛出 ValueError (JSONDecodeError)
                    error_detail = response.json().get('detail', '未知错误')
                except ValueError:
                    # 兜底使用文本片段，避免捕获 BaseException
                    error_detail = response.text[:100] if response.text else '未知错误'
                await update.message.reply_text(f"❌ 获取内容失败: {error_detail}")
                return
            
            contents = response.json()
            
            if not contents or len(contents) == 0:
                tag_hint = f" (标签: {tag})" if tag else ""
                await update.message.reply_text(f"📭 暂无待推送的内容{tag_hint}")
                return
            
            content = contents[0]
            content_id = content.get("id")
            
            if not content_id:
                logger.error("内容缺少id字段")
                await update.message.reply_text("❌ 内容数据异常")
                return
            
            # 发送到频道
            await self.send_content_to_channel(content, context)
            
            # 异步标记为已推送（不阻塞响应）
            asyncio.create_task(self._mark_pushed_async(content_id))
            
            title = content.get('title') or content.get('url', '未知内容')
            await update.message.reply_text(f"✅ 已发送: {title[:50]}..." if len(title) > 50 else f"✅ 已发送: {title}")
            logger.info(f"Bot /get 响应已发送: content_id={content_id}, title={title[:50]}")
            
        except Exception as e:
            logger.exception(f"处理 /get 命令失败")  # 使用exception记录完整堆栈
            error_msg = str(e)[:200] if str(e) else "未知错误"  # 限制错误消息长度
            try:
                await update.message.reply_text(f"❌ 发送失败: {error_msg}")
            except Exception as reply_error:
                logger.error(f"回复消息失败: {reply_error}")
    
    async def _mark_pushed_async(self, content_id: int):
        """异步标记内容为已推送"""
        try:
            client = await self._get_client()
            await client.post(
                f"{self.api_base}/bot/mark-pushed",
                json={
                    "content_id": content_id,
                    "target_platform": self.target_platform
                }
            )
        except Exception as e:
            logger.warning(f"标记已推送失败: content_id={content_id}, error={e}")
    
    async def status_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """处理 /status 命令 - 查看系统状态"""
        if not update or not update.message:
            return
        
        user = update.effective_user
        logger.info(f"Bot /status 命令: user={user.username or user.id}")
            
        try:
            client = await self._get_client()
            
            try:
                response = await client.get(f"{self.api_base}/health", timeout=5.0)
            except httpx.TimeoutException:
                await update.message.reply_text("⏱️ 请求超时")
                return
            except httpx.RequestError as e:
                logger.error(f"健康检查请求错误: {e}")
                await update.message.reply_text("❌ 无法连接到后端服务")
                return
            
            if response.status_code != 200:
                await update.message.reply_text(f"❌ 服务异常 (状态码: {response.status_code})")
                return
                
            data = response.json()
            status = data.get('status', 'unknown')
            queue_size = data.get('queue_size', '?')
            
            status_icon = "✅" if status == "healthy" else "⚠️"
            
            await update.message.reply_text(
                f"📊 系统状态\n\n"
                f"{status_icon} 状态: {status}\n"
                f"📦 队列任务数: {queue_size}"
            )
            logger.info(f"Bot /status 响应已发送: status={status}, queue_size={queue_size}")
            except Exception as e:
                logger.exception("处理 /status 命令失败")
                try:
                    await update.message.reply_text("❌ 获取状态失败")
                except Exception as reply_err:
                    # 回复失败为 best-effort，不应掩盖原始异常
                    logger.warning("回复 /status 失败: %s", reply_err)

    async def send_content_to_channel(self, content: dict, context: ContextTypes.DEFAULT_TYPE):
        """发送内容到频道"""
        if not content:
            raise ValueError("内容为空")
            
        try:
            text = format_content_for_tg(content)
            
            # 限制文本长度（Telegram限制）
            max_caption_length = 1024
            max_message_length = 4096
            
            cover_url = content.get('cover_url')
            
            if cover_url and isinstance(cover_url, str) and cover_url.strip():
                # 有封面图，发送图片+描述
                if len(text) > max_caption_length:
                    text = text[:max_caption_length-3] + "..."
                
                try:
                    await context.bot.send_photo(
                        chat_id=settings.telegram_channel_id,
                        photo=cover_url.strip(),
                        caption=text,
                        parse_mode='HTML',
                        read_timeout=30,
                        write_timeout=30
                    )
                except Exception as photo_error:
                    # 图片发送失败，降级为纯文本
                    logger.warning(f"发送图片失败，降级为文本: {photo_error}")
                    if len(text) > max_message_length:
                        text = text[:max_message_length-3] + "..."
                    await context.bot.send_message(
                        chat_id=settings.telegram_channel_id,
                        text=text,
                        parse_mode='HTML',
                        disable_web_page_preview=False
                    )
            else:
                # 无封面图，发送纯文本
                if len(text) > max_message_length:
                    text = text[:max_message_length-3] + "..."
                    
                await context.bot.send_message(
                    chat_id=settings.telegram_channel_id,
                    text=text,
                    parse_mode='HTML',
                    disable_web_page_preview=False
                )
        except Exception as e:
            logger.exception("发送到频道失败")
            raise

    async def _verify_connection(self, application: Application) -> bool:
        """验证Bot连接和配置"""
        try:
            logger.info("正在验证 Telegram Bot 连接...")
            
            # 获取Bot信息
            bot_info = await application.bot.get_me()
            logger.info(f"✅ Bot 连接成功: @{bot_info.username} (ID: {bot_info.id})")
            
            # 验证频道访问权限
            try:
                chat = await application.bot.get_chat(settings.telegram_channel_id)
                logger.info(f"✅ 频道访问验证成功: {chat.title or chat.username or settings.telegram_channel_id}")
            except Exception as e:
                logger.error(f"❌ 无法访问频道 {settings.telegram_channel_id}: {e}")
                logger.error("请检查：1) 频道ID是否正确  2) Bot是否已添加为频道管理员")
                return False
            
            # 验证后端API连接
            try:
                client = await self._get_client()
                response = await client.get(f"{self.api_base}/health", timeout=5.0)
                if response.status_code == 200:
                    logger.info(f"✅ 后端API连接成功: {self.api_base}")
                else:
                    logger.warning(f"⚠️  后端API响应异常 (状态码: {response.status_code})")
            except Exception as e:
                logger.error(f"❌ 无法连接到后端API {self.api_base}: {e}")
                logger.error("请确保后端服务已启动")
                return False
            
            return True
            
        except Exception as e:
            logger.error(f"❌ Bot 连接验证失败: {e}")
            if "TimedOut" in str(type(e).__name__) or "timeout" in str(e).lower():
                logger.error("连接超时，请检查：")
                logger.error("1) 网络连接是否正常")
                logger.error("2) 代理配置是否正确 (如果使用代理)")
                logger.error("3) Bot Token 是否有效")
            return False
    
    def run(self):
        """运行Bot"""
        if not settings.telegram_bot_token or not settings.telegram_bot_token.get_secret_value():
            logger.error("未配置 TELEGRAM_BOT_TOKEN")
            return
        
        if not settings.telegram_channel_id:
            logger.error("未配置 TELEGRAM_CHANNEL_ID")
            return
        
        # 创建应用
        builder = Application.builder().token(settings.telegram_bot_token.get_secret_value())
        
        # 配置代理
        if hasattr(settings, 'telegram_proxy_url') and settings.telegram_proxy_url:
            logger.info(f"使用代理: {settings.telegram_proxy_url}")
            builder.proxy(settings.telegram_proxy_url)
            builder.get_updates_proxy(settings.telegram_proxy_url)
            builder.connect_timeout(10)
            builder.read_timeout(10)
        else:
            logger.info("未配置代理，直接连接")
            
        application = builder.build()
        
        # 注册命令处理器
        application.add_handler(CommandHandler("start", self.start_command))
        application.add_handler(CommandHandler("get", self.get_command))
        application.add_handler(CommandHandler("status", self.status_command))
        
        # 启动前验证连接
        logger.info("=" * 60)
        logger.info("正在启动 Telegram Bot...")
        logger.info("=" * 60)
        
        # 使用 asyncio 运行异步验证和启动
        async def run_with_verification():
            async with application:
                # 先初始化
                await application.initialize()
                await application.start()
                
                # 验证连接
                if not await self._verify_connection(application):
                    logger.error("=" * 60)
                    logger.error("Bot 连接验证失败，请检查配置后重试")
                    logger.error("=" * 60)
                    await application.stop()
                    return
                
                logger.info("=" * 60)
                logger.info("✅ Bot 已启动，开始监听消息...")
                logger.info("按 Ctrl+C 停止")
                logger.info("=" * 60)
                
                # 启动轮询
                await application.updater.start_polling(
                    allowed_updates=Update.ALL_TYPES,
                    drop_pending_updates=True
                )
                
                # 等待停止信号
                stop_event = asyncio.Event()
                
                # 等待停止信号（可由外部通过 stop_event.set() 触发）
                # 注意：不在此处注册全局信号处理，运行环境可自行管理进程信号。
                try:
                    await stop_event.wait()
                except asyncio.CancelledError:
                    pass
                
                logger.info("收到停止信号，正在关闭...")
                
                # 停止轮询（设置超时避免永久等待）
                try:
                    await asyncio.wait_for(application.updater.stop(), timeout=5.0)
                except asyncio.TimeoutError:
                    logger.warning("停止轮询超时，强制继续")
                except Exception as e:
                    logger.warning(f"停止轮询时出错: {e}")
                
                # 停止应用（设置超时）
                try:
                    await asyncio.wait_for(application.stop(), timeout=3.0)
                except asyncio.TimeoutError:
                    logger.warning("停止应用超时，强制继续")
                except Exception as e:
                    logger.warning(f"停止应用时出错: {e}")
                
                # 清理资源
                await self.close()
        
        try:
            asyncio.run(run_with_verification())
        except KeyboardInterrupt:
            logger.info("\nBot 已停止")


if __name__ == "__main__":
    bot = VaultStreamBot()
    bot.run()
