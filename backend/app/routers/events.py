"""
SSE (Server-Sent Events) 实时事件推送路由
"""
import json
from fastapi import APIRouter, Depends, Header
from fastapi.responses import StreamingResponse
from app.core.events import event_bus
from app.core.dependencies import require_api_token

router = APIRouter()


@router.get("/events/subscribe")
async def subscribe_events(
    last_event_id: int | None = Header(None, ge=0, alias="Last-Event-ID"),
    _: None = Depends(require_api_token),
):
    """SSE事件订阅端点，支持 Last-Event-ID 断线续传。
    
    客户端通过此端点订阅实时事件：
    - content_created: 内容新增（收藏库）
    - content_updated: 内容更新（解析完成/编辑）
    - content_deleted: 内容删除
    - content_pushed: 内容已推送（分发）
    - distribution_push_success: 队列项推送成功
    - distribution_push_failed: 队列项推送失败
    - queue_updated: 队列更新
    - bot_sync_progress: Bot 同步进度
    - bot_sync_completed: Bot 同步完成
    - ping: 心跳保活
    
    断线续传：客户端重连时携带 `Last-Event-ID` 头，服务端会先重放该 ID
    之后的所有事件，再进入实时推送。
    """
    async def event_stream():
        async for message in event_bus.subscribe(last_event_id):
            prefix = f"id: {message['id']}\n" if "id" in message else ""
            payload = json.dumps(message["data"], ensure_ascii=False)
            yield f"{prefix}event: {message['event']}\ndata: {payload}\n\n"

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@router.get("/events/health")
async def events_health(_: None = Depends(require_api_token)):
    """事件系统健康检查"""
    return event_bus.get_diagnostics()
