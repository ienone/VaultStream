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
    
    使用方式：
    ```javascript
    const eventSource = new EventSource('/api/v1/events/subscribe');
    eventSource.addEventListener('content_pushed', (e) => {
      const data = JSON.parse(e.data);
      console.log('Content pushed:', data);
    });
    ```
    """
    async def event_stream():
        client_id = id(asyncio.current_task())
        try:
            logger.info(f"SSE client connected: {client_id}")
            
            # 发送连接成功消息
            yield f"event: connected\ndata: {json.dumps({'message': 'Connected to VaultStream events', 'client_id': client_id}, ensure_ascii=False)}\n\n"
            
            # 订阅事件流
            async for message in event_bus.subscribe():
                try:
                    event_type = message.get("event", "message")
                    data = message.get("data", {})
                    
                    # SSE格式: event: xxx\ndata: {...}\n\n
                    event_data = json.dumps(data, ensure_ascii=False)
                    yield f"event: {event_type}\ndata: {event_data}\n\n"
                    
                except Exception as e:
                    logger.error(f"Error formatting SSE message: {e}")
                    # 继续处理下一个消息，不中断连接
                    continue
                
        except asyncio.CancelledError:
            logger.info(f"SSE client disconnected normally: {client_id}")
            raise  # 重新抛出，确保清理逻辑执行
        except Exception as e:
            logger.error(f"SSE event stream error for client {client_id}: {e}", exc_info=True)
            # 发送错误事件，然后关闭连接
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
            "X-Accel-Buffering": "no",  # 禁用 Nginx 缓冲
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
