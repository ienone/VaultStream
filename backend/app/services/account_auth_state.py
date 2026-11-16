"""Credential-scoped authentication observations shared by account and business flows."""
import hashlib
import json

from sqlalchemy import text

from app.adapters.base import PlatformAdapter
from app.core.db_adapter import AsyncSessionLocal
from app.core.events import event_bus
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.models import SystemSetting
from app.services.config_service import ConfigService


def credential_id(platform: str, cookie: str | None) -> str:
    cookies = PlatformAdapter.parse_cookie_str(cookie or "")
    identity_keys = {
        "zhihu": "z_c0", "xiaohongshu": "web_session", "twitter": "auth_token",
        "weibo": "SUB", "bilibili": "SESSDATA",
    }
    key = identity_keys.get(platform)
    identity = {key: cookies[key]} if key in cookies else cookies
    return hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()


def account_login(platform: str, cookie: str | None, observation: dict | None) -> str:
    if not cookie:
        return "not_configured"
    if observation and observation.get("credential_id") == credential_id(platform, cookie):
        if observation.get("status") == "invalid":
            return "invalid"
    return "configured"


async def record_account_auth(platform: str, *, is_valid: bool | None, expected_cookie: str | None) -> None:
    """Persist only evidence for the credential actually checked; inbox is a projection."""
    fingerprint = credential_id(platform, expected_cookie)
    async with AsyncSessionLocal() as db:
        await db.execute(text("BEGIN IMMEDIATE"))
        config = await ConfigService.snapshot(db)
        current_cookie = await config.get_platform_cookie_string(platform)
        if credential_id(platform, current_cookie) != fingerprint:
            await db.rollback()
            return
        status = ("not_configured" if not current_cookie else "configured" if is_valid is None
                  else "valid" if is_valid else "invalid")
        key = f"account_auth:{platform}"
        row = await db.get(SystemSetting, key)
        if (is_valid is None and row is not None
                and row.value.get("credential_id") == fingerprint):
            await db.rollback()
            return
        value = {"credential_id": fingerprint, "status": status, "checked_at": utcnow().isoformat()}
        changed = row is None or (row.value or {}).get("status") != status or (row.value or {}).get("credential_id") != fingerprint
        if row is None:
            db.add(SystemSetting(key=key, value=value, category="account_auth"))
        else:
            row.value = value
        await db.commit()
    from app.services.notification_inbox import safely_sync_account_auth_notification
    await safely_sync_account_auth_notification(platform, is_valid=is_valid, configured=bool(current_cookie))
    if changed:
        await event_bus.publish("account_auth_updated", {"platform": platform})


async def observe_account_auth(platform: str, *, is_valid: bool | None, expected_cookie: str | None) -> None:
    try:
        await record_account_auth(platform, is_valid=is_valid, expected_cookie=expected_cookie)
    except Exception:
        logger.exception("无法保存 {} 的认证检查结果", platform)
