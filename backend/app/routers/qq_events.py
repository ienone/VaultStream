"""NapCat HTTP 事件上报，按配置中的 OneBot token 校验 HMAC。"""
import hashlib
import hmac
import json
from fastapi import APIRouter, BackgroundTasks, HTTPException, Request
from pydantic import BaseModel
from app.core.database import AsyncSessionLocal
from app.models import BotConfig, BotConfigPlatform
from app.services.qq_messages import accept_message, reply_when_parsed

router = APIRouter()


class QQEventResponse(BaseModel):
    pass


@router.post('/bot/qq/{config_id}/events', response_model=QQEventResponse)
async def receive_event(config_id: int, request: Request, background: BackgroundTasks):
    body = await request.body()
    async with AsyncSessionLocal() as db:
        config = await db.get(BotConfig, config_id)
        if not config or not config.enabled or config.platform != BotConfigPlatform.QQ or not config.napcat_access_token:
            raise HTTPException(403, 'QQ Bot is not enabled')
        expected = 'sha1=' + hmac.new(config.napcat_access_token.encode(), body, hashlib.sha1).hexdigest()
        if not hmac.compare_digest(expected, request.headers.get('x-signature', '')):
            raise HTTPException(403, 'Invalid event signature')
    event = json.loads(body)
    ids, target = await accept_message(config_id, event)
    background.add_task(reply_when_parsed, ids, target)
    return QQEventResponse()
