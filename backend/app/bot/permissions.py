"""Effective Telegram permissions for commands, callbacks, and captures."""
from sqlalchemy import select

from app.core.config import settings
from app.core.db_adapter import AsyncSessionLocal
from app.models import SystemSetting

from .messages import MSG_NO_PERMISSION, MSG_BLACKLISTED, MSG_ADMIN_ONLY


async def check_permission(user_id: int | str, *, require_admin: bool = False) -> tuple[bool, str | None]:
    keys = ("telegram_admin_ids", "telegram_whitelist_ids", "telegram_blacklist_ids")
    async with AsyncSessionLocal() as db:
        overrides = dict((await db.execute(
            select(SystemSetting.key, SystemSetting.value).where(SystemSetting.key.in_(keys))
        )).all())
    admins, allowed, blocked = (
        {item.strip() for item in str(overrides.get(key, getattr(settings, key)) or "").split(",") if item.strip()}
        for key in keys
    )
    uid = str(user_id)
    if uid in blocked:
        return False, MSG_BLACKLISTED
    if uid in admins:
        return True, None
    if require_admin:
        return False, MSG_ADMIN_ONLY
    return (True, None) if uid in allowed else (False, MSG_NO_PERMISSION)
