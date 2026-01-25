"""
Bot 回调处理模块
"""
import httpx
from telegram import Update
from telegram.ext import ContextTypes
from app.core.logging import logger
from .permissions import get_permission_manager


async def button_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """处理按钮回调"""
    query = update.callback_query
    await query.answer()
    
    user = update.effective_user
    callback_data = query.data
    
    logger.info(f"Bot 按钮回调: user={user.username}(ID:{user.id}), data={callback_data}")
    
    # 获取依赖
    perm_manager = get_permission_manager(context.bot_data)
    http_client: httpx.AsyncClient = context.bot_data.get("http_client")
    api_base = context.bot_data.get("api_base")
    
    # 权限检查 (需要管理员)
    allowed, reason = perm_manager.check_permission(user.id, require_admin=True)
    if not allowed:
        try:
            await query.edit_message_text(reason)
        except Exception:
            pass
        return
    
    try:
        # 解析回调数据: action_contentid
        parts = callback_data.split("_", 1)
        if len(parts) != 2:
            await query.edit_message_text("无效的操作")
            return
        
        action, content_id = parts
        content_id = int(content_id)
        
        if action == "delete":
            # 删除内容
            try:
                response = await http_client.delete(
                    f"{api_base}/contents/{content_id}",
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
