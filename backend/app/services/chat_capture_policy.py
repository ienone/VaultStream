"""One write boundary for Bot saves; link previews never enter this service."""
from __future__ import annotations

from app.core.config import settings
from app.services.settings_service import get_setting_value_fresh

CHAT_SOURCES = {"qq_bot", "telegram_bot"}


async def require_chat_capture_enabled() -> None:
    if await get_setting_value_fresh("chat_capture_enabled", True) is not True:
        raise ValueError("机器人转存已关闭。")


async def require_chat_capture_admin(source: str, user_id: str) -> None:
    if source == "qq_bot":
        options = await get_setting_value_fresh("qq_bot_agent", {})
        admins = options.get("admin_qq", []) if options.get("enabled") is True else []
    elif source == "telegram_bot":
        value = await get_setting_value_fresh("telegram_admin_ids", settings.telegram_admin_ids)
        admins = str(value or "").split(",")
    else:
        raise ValueError("不支持的聊天入口。")
    if not user_id or user_id not in {str(value).strip() for value in admins}:
        raise ValueError("只有管理员可以要求机器人转存收藏。")


async def authorize_chat_capture(source: str, context: dict | None) -> dict | None:
    """Run before any content/queue/file write, regardless of the URL platform."""
    if source not in CHAT_SOURCES:
        return context
    await require_chat_capture_enabled()
    origin = dict(context or {})
    await require_chat_capture_admin(source, str(origin.get("user_id") or ""))
    request_text = str(origin.pop("request_text", ""))
    instruction = origin.pop("save_instruction", "")
    if (not isinstance(instruction, str) or not instruction.strip()
            or len(instruction) > 1000 or instruction not in request_text):
        raise ValueError("没有收到管理员明确的转存请求，未收藏。")
    # Recheck immediately before entering the write boundary.
    await require_chat_capture_enabled()
    origin["save_instruction"] = instruction
    return origin
