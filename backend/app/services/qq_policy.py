"""QQ 会话接收策略与所有发送入口共用的小时限频。"""
import time
from sqlalchemy import text
from app.core.database import AsyncSessionLocal
from app.models import SystemSetting
from app.services.config_service import ConfigService


class QQRateLimited(RuntimeError):
    def __init__(self, retry_at: float):
        super().__init__("该群已达到每小时发送上限")
        self.retry_at = retry_at


async def reserve_group_send(group_id: str) -> None:
    policies = await ConfigService().get_value('qq_chat_policies', {})
    limit = policies.get(str(group_id), {}).get('max_messages_per_hour')
    if not limit:
        return
    now = time.time()
    key = f'qq_send_window:{group_id}'
    async with AsyncSessionLocal() as db:
        await db.execute(text('BEGIN IMMEDIATE'))
        row = await db.get(SystemSetting, key)
        times = [t for t in (row.value if row else []) if t > now - 3600]
        if len(times) >= int(limit):
            raise QQRateLimited(min(times) + 3600)
        times.append(now)
        if row:
            row.value = times
        else:
            db.add(SystemSetting(key=key, value=times, category='runtime'))
        await db.commit()
