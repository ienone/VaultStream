"""
SSE (Server-Sent Events) 实时事件推送路由
"""
import asyncio
import json
from fastapi import APIRouter, Depends, Header
from fastapi.responses import StreamingResponse
from typing import Optional
from app.core.events import event_bus
from app.core.dependencies import require_api_token
from app.core.logging import logger

router = APIRouter()


@router.get("/events/subscribe")
async def subscribe_events(
    last_event_id: Optional[str] = Header(None, alias="Last-Event-ID"),
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
    # 解析 Last-Event-ID（可能来自 Header 或 query param）
    replay_from_id: int | None = None
    if last_event_id:
        try:
            replay_from_id = int(last_event_id)
        except (ValueError, TypeError):
            pass

    async def event_stream():
        client_id = id(asyncio.current_task())
        try:
            logger.info(f"SSE client connected: {client_id}, last_event_id={replay_from_id}")
            
            # 发送连接成功消息
            yield f"event: connected\ndata: {json.dumps({'message': 'Connected to VaultStream events', 'client_id': client_id}, ensure_ascii=False)}\n\n"

            # 断线续传：重放 Last-Event-ID 之后的事件
            if replay_from_id is not None:
                missed_events = await event_bus.replay_events_since(replay_from_id)
                if missed_events:
                    logger.info(f"Replaying {len(missed_events)} missed events for client {client_id}")
                for evt in missed_events:
                    event_data = json.dumps(evt["data"], ensure_ascii=False)
                    yield f"id: {evt['id']}\nevent: {evt['event']}\ndata: {event_data}\n\n"

            # 订阅实时事件流
            async for message in event_bus.subscribe():
                try:
                    event_type = message.get("event", "message")
                    data = message.get("data", {})
                    event_id = message.get("id")
                    
                    event_data = json.dumps(data, ensure_ascii=False)
                    # 包含 id 字段以支持客户端 Last-Event-ID 自动追踪
                    if event_id is not None:
                        yield f"id: {event_id}\nevent: {event_type}\ndata: {event_data}\n\n"
                    else:
                        yield f"event: {event_type}\ndata: {event_data}\n\n"
                    
                except Exception as e:
                    logger.error(f"Error formatting SSE message: {e}")
                    continue
                
        except asyncio.CancelledError:
            logger.info(f"SSE client disconnected normally: {client_id}")
            raise
        except Exception as e:
            logger.error(f"SSE event stream error for client {client_id}: {e}", exc_info=True)
            try:
                yield f"event: error\ndata: {json.dumps({'error': str(e)}, ensure_ascii=False)}\n\n"
            except:
                pass
    
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
    from app.core.events import EventBus
    
    subscriber_count = len(EventBus._subscribers)
    
    return {
        "status": "healthy",
        "active_subscribers": subscriber_count,
        "event_bus": "ready"
    }
