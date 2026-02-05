"""
SSE (Server-Sent Events) 实时事件推送路由
"""
import asyncio
import json
from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse
from app.core.events import event_bus
from app.core.dependencies import require_api_token
from app.core.logging import logger

router = APIRouter()


@router.get("/events/subscribe")
async def subscribe_events(
    _: None = Depends(require_api_token),
):
    """SSE事件订阅端点
    
    客户端通过此端点订阅实时事件：
    - content_updated: 内容更新
    - content_deleted: 内容删除
    - content_re_parsed: 内容重新解析
    - queue_reordered: 队列重新排序
    - bot_status_changed: Bot状态变化
    
    使用方式：
    ```
    EventSource('/api/v1/events/subscribe')
    ```
    """
    async def event_stream():
        try:
            logger.info("新的SSE客户端连接")
            
            # 发送连接成功消息
            yield f"event: connected\ndata: {json.dumps({'message': 'Connected to VaultStream events'})}\n\n"
            
            # 订阅事件流
            async for message in event_bus.subscribe():
                event_type = message.get("event", "message")
                data = message.get("data", {})
                
                # SSE格式: event: xxx\ndata: {...}\n\n
                event_data = json.dumps(data, ensure_ascii=False)
                yield f"event: {event_type}\ndata: {event_data}\n\n"
                
        except asyncio.CancelledError:
            logger.info("SSE客户端断开连接")
        except Exception as e:
            logger.error(f"SSE事件流错误: {e}")
            yield f"event: error\ndata: {json.dumps({'error': str(e)})}\n\n"
    
    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",  # 禁用Nginx缓冲
        }
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
