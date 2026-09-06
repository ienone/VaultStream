"""
Bot 回调处理模块
"""
import httpx
from telegram import Update
from telegram.ext import ContextTypes
from app.core.logging import logger
from .permissions import get_permission_manager


def _get_api_headers(context: ContextTypes.DEFAULT_TYPE) -> dict[str, str]:
    token = context.bot_data.get("api_token")
    return {"X-API-Token": token} if token else {}


def _api_error_message(response: httpx.Response) -> str:
    try:
        payload = response.json()
    except Exception:
        return f"HTTP {response.status_code}"
    if not isinstance(payload, dict):
        return f"HTTP {response.status_code}"
    detail = payload.get("detail")
    if isinstance(detail, dict):
        return str(detail.get("message") or detail.get("error") or response.status_code)
    return str(payload.get("error_message") or detail or response.status_code)


async def button_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """处理按钮回调"""
    query = update.callback_query
    await query.answer()
    
    user = update.effective_user
    callback_data = query.data or ""
    
    logger.info(f"Bot 按钮回调: user={user.username}(ID:{user.id}), data={callback_data}")
    
    # 获取依赖
    perm_manager = get_permission_manager(context.bot_data)
    http_client: httpx.AsyncClient = context.bot_data.get("http_client")
    api_base = context.bot_data.get("api_base")
    
    is_agent_confirmation = callback_data.startswith("agent-confirm:")
    # 内容删除始终需要管理员；Agent 确认允许原请求人处理，归属在下方核验。
    allowed, reason = perm_manager.check_permission(
        user.id,
        require_admin=not is_agent_confirmation,
    )
    if not allowed:
        try:
            await query.edit_message_text(reason)
        except Exception:
            pass
        return
    
    try:
        if callback_data.startswith("agent-confirm:"):
            parts = callback_data.split(":", 2)
            if len(parts) != 3 or parts[1] not in {"approve", "reject"}:
                await query.edit_message_text("无效的确认操作")
                return
            confirmation_id = parts[2].strip()
            if not confirmation_id:
                await query.edit_message_text("确认请求缺少 ID")
                return
            approved = parts[1] == "approve"
            detail_response = await http_client.get(
                f"{api_base}/agent/confirmations/{confirmation_id}",
                timeout=10.0,
                headers=_get_api_headers(context),
            )
            if detail_response.status_code != 200:
                await query.edit_message_text(
                    f"确认请求不可用: {_api_error_message(detail_response)}"
                )
                return
            detail = detail_response.json()
            owns_request = str(detail.get("session_id") or "") == f"tg-{user.id}"
            is_admin, _ = perm_manager.check_permission(user.id, require_admin=True)
            if not owns_request and not is_admin:
                await query.edit_message_text("只能处理自己发起的 Agent 确认请求")
                return
            response = await http_client.post(
                f"{api_base}/agent/confirmations/{confirmation_id}/decide",
                json={"approved": approved},
                timeout=20.0,
                headers=_get_api_headers(context),
            )
            if response.status_code != 200:
                await query.edit_message_text(
                    f"确认处理失败: {_api_error_message(response)}"
                )
                return
            data = response.json()
            tool = str(data.get("tool") or "Agent 操作")
            result_message = str(data.get("message") or "").strip()
            action_text = "已批准" if approved else "已拒绝"
            text = f"✓ {action_text} {tool}"
            if result_message:
                text = f"{text}\n{result_message}"
            await query.edit_message_text(text, reply_markup=None)
            return

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
                    timeout=5.0,
                    headers=_get_api_headers(context),
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
