"""NapCat HTTP 事件上报，按配置中的 OneBot token 校验 HMAC。"""
import hashlib
import hmac
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel
from app.core.database import AsyncSessionLocal
from app.models import BotConfig, BotConfigPlatform

router = APIRouter()


class QQEventResponse(BaseModel):
    reply: str | None = None


@router.post('/bot/qq/{config_id}/events', response_model=QQEventResponse, response_model_exclude_none=True)
async def receive_event(config_id: int, request: Request):
    body = await request.body()
    async with AsyncSessionLocal() as db:
        config = await db.get(BotConfig, config_id)
        if not config or not config.enabled or config.platform != BotConfigPlatform.QQ or not config.napcat_access_token:
            raise HTTPException(403, 'QQ Bot is not enabled')
        expected = 'sha1=' + hmac.new(config.napcat_access_token.encode(), body, hashlib.sha1).hexdigest()
        if not hmac.compare_digest(expected, request.headers.get('x-signature', '')):
            raise HTTPException(403, 'Invalid event signature')
    # NapCat still reports events to this signed endpoint. Capture belongs to
    # the explicit Bot tool; HTTP events never imply a request to save.
    return QQEventResponse()
