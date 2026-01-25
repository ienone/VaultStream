"""
Bot 命令处理模块
"""
import time
import httpx
import logging
import asyncio
from typing import Optional
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ContextTypes

from app.core.logging import logger
from app.core.config import settings
from app.push.telegram import build_telegram_payload, send_to_telegram
from .messages import HELP_TEXT_START, HELP_TEXT_FULL, MSG_API_ERROR, MSG_TIMEOUT
from .permissions import get_permission_manager

# --- 辅助函数 ---

async def _get_client(context: ContextTypes.DEFAULT_TYPE) -> httpx.AsyncClient:
    """从 context 获取 httpx client"""
    return context.bot_data.get("http_client")

def _get_api_base(context: ContextTypes.DEFAULT_TYPE) -> str:
    """从 context 获取 API base URL"""
    return context.bot_data.get("api_base")

def _get_target_platform(context: ContextTypes.DEFAULT_TYPE) -> str:
    return context.bot_data.get("target_platform")

async def _check_perm(update: Update, context: ContextTypes.DEFAULT_TYPE, require_admin: bool = False) -> bool:
    """统一权限检查 helper"""
    user = update.effective_user
    if not user:
        return False
        
    perm_manager = get_permission_manager(context.bot_data)
    if not perm_manager:
        # 如果未配置权限管理器，默认允许？或者拒绝？为了安全默认拒绝
        logger.error("Permission manager not found in bot_data")
        await update.message.reply_text("系统错误：权限配置缺失")
        return False
        
    allowed, reason = perm_manager.check_permission(user.id, require_admin=require_admin)
    if not allowed:
        await update.message.reply_text(reason)
        return False
    return True

# --- 命令处理器 ---

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """处理 /start 命令"""
    user = update.effective_user
    logger.info(f"Bot /start 命令: user={user.username}(ID:{user.id})")
    
    if not await _check_perm(update, context):
        return
    
    await update.message.reply_text(HELP_TEXT_START, parse_mode='HTML')

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """处理 /help 命令"""
    user = update.effective_user
    logger.info(f"Bot /help 命令: user={user.username}(ID:{user.id})")
    
    if not await _check_perm(update, context):
        return
    
    await update.message.reply_text(HELP_TEXT_FULL, parse_mode='HTML')

async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """处理 /status 命令"""
    start_time = time.time()
    user = update.effective_user
    logger.info(f"Bot /status 命令: user={user.username}(ID:{user.id})")
    
    if not await _check_perm(update, context):
        return
        
    try:
        client = await _get_client(context)
        api_base = _get_api_base(context)
        
        try:
            api_start = time.time()
            response = await client.get(f"{api_base}/health", timeout=5.0)
            api_time = time.time() - api_start
        except httpx.TimeoutException:
            await update.message.reply_text(MSG_TIMEOUT)
            return
        except httpx.RequestError:
            await update.message.reply_text(MSG_API_ERROR)
            return
        
        if response.status_code != 200:
            await update.message.reply_text(f"服务异常 (状态码: {response.status_code})")
            return
            
        data = response.json()
        status = data.get('status', 'unknown')
        queue_size = data.get('queue_size', '?')
        
        status_icon = "✓" if status == "ok" else "✗"
        
        await update.message.reply_text(
            f"<b>系统状态</b>\n\n"
            f"{status_icon} 状态: {status}\n"
            f"队列任务数: {queue_size}",
            parse_mode='HTML'
        )
        logger.info(f"Bot /status 完成, 耗时={time.time() - start_time:.3f}s")
    except Exception as e:
        logger.exception("处理 /status 命令失败")
        await update.message.reply_text("获取状态失败")

async def list_tags_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """处理 /list_tags 命令"""
    user = update.effective_user
    logger.info(f"Bot /list_tags 命令: user={user.username}(ID:{user.id})")
    
    if not await _check_perm(update, context):
        return
        
    try:
        client = await _get_client(context)
        api_base = _get_api_base(context)
        
        response = await client.get(f"{api_base}/tags", timeout=5.0)
        
        if response.status_code != 200:
            await update.message.reply_text("无法获取标签列表")
            return
        
        tags_data = response.json()
        
        if not tags_data:
            await update.message.reply_text("暂无任何标签")
            return
        
        tag_lines = []
        for tag_item in tags_data[:20]:
            tag_lines.append(f"• {tag_item['name']}: {tag_item['count']}")
        
        message = "<b>可用标签</b>\n\n" + "\n".join(tag_lines)
        if len(tags_data) > 20:
            message += f"\n\n还有 {len(tags_data) - 20} 个标签"
        
        await update.message.reply_text(message, parse_mode='HTML')
        
    except Exception:
        logger.exception("/list_tags 命令失败")
        await update.message.reply_text("获取标签列表失败")

# --- 内容获取相关命令 ---

async def get_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """处理 /get 命令"""
    tag = None
    if context.args and len(context.args) > 0:
        tag = context.args[0].strip()
    await _get_content_by_filter(update, context, tag=tag)

async def get_tag_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """处理 /get_tag 命令"""
    if not context.args:
        await update.message.reply_text(
            "请指定标签\n\n用法: <code>/get_tag 标签名</code>",
            parse_mode='HTML'
        )
        return
    tag = context.args[0].strip()
    await _get_content_by_filter(update, context, tag=tag)

async def get_twitter_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """处理 /get_twitter 命令"""
    await _get_content_by_filter(update, context, platform="twitter")

async def get_bilibili_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """处理 /get_bilibili 命令"""
    await _get_content_by_filter(update, context, platform="bilibili")

async def _get_content_by_filter(
    update: Update, 
    context: ContextTypes.DEFAULT_TYPE,
    tag: Optional[str] = None,
    platform: Optional[str] = None
):
    """通用内容获取逻辑"""
    user = update.effective_user
    if not user: return
    
    if not await _check_perm(update, context):
        return

    filter_desc = []
    if tag: filter_desc.append(f"标签={tag}")
    if platform: filter_desc.append(f"平台={platform}")
    
    logger.info(f"Bot 获取内容: user={user.username}(ID:{user.id}) {filter_desc}")
    
    try:
        client = await _get_client(context)
        api_base = _get_api_base(context)
        target_platform = _get_target_platform(context)
        
        payload = {
            "target_platform": target_platform,
            "limit": 1
        }
        if tag: payload["tag"] = tag
        if platform: payload["platform"] = platform
        
        try:
            response = await client.post(
                f"{api_base}/bot/get-content",
                json=payload,
                timeout=10.0
            )
        except httpx.TimeoutException:
            await update.message.reply_text(MSG_TIMEOUT)
            return
        except httpx.RequestError:
            await update.message.reply_text(MSG_API_ERROR)
            return
            
        if response.status_code != 200:
            error_msg = "未知错误"
            try:
                error_msg = response.json().get('detail', '未知错误')
            except: pass
            await update.message.reply_text(f"获取内容失败: {error_msg}")
            return
            
        contents = response.json()
        if not contents:
            await update.message.reply_text("暂无符合条件的内容")
            return
            
        content = contents[0]
        content_id = content.get("id")
        
        # 发送到频道 (模拟)
        # 注意：这里我们实际直接回复给用户，或者发送到频道？
        # 原代码是 self.send_content_to_channel(content, context)
        # 这里需要 context.bot ...
        
        # 复用原逻辑：发送到配置的 channel
        channel_id = context.bot_data.get("channel_id")
        
        # 构建消息并发送到Channel
        text, media_items = build_telegram_payload(content)
        
        # 按钮
        keyboard = [[InlineKeyboardButton("🗑️ 删除", callback_data=f"delete_{content_id}")]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await send_to_telegram(
            context.bot,
            channel_id,
            text,
            media_items,
            reply_markup=reply_markup
        )
        
        # 标记为已推送
        asyncio.create_task(_mark_pushed_async(client, api_base, content_id, target_platform, str(channel_id)))
        
        # 回复触发命令的用户
        title = content.get('title') or content.get('url', '未知内容')
        title_short = title[:50] + "..." if len(title) > 50 else title
        platform_name = content.get('platform', '')
        await update.message.reply_text(f"已发送: {title_short}\n平台: {platform_name}")
        
    except Exception as e:
        logger.exception("获取内容失败")
        await update.message.reply_text(f"发送失败: {str(e)[:100]}")

async def _mark_pushed_async(client: httpx.AsyncClient, api_base: str, content_id: int, target_platform: str, target_id: str):
    """异步标记已推送"""
    try:
        await client.post(
            f"{api_base}/bot/mark-pushed",
            json={
                "content_id": content_id,
                "target_platform": target_platform,
                "target_id": target_id
            }
        )
    except Exception as e:
        logger.warning(f"标记已推送失败 {content_id}: {e}")
