import pytest
import asyncio
import json
from unittest.mock import patch, MagicMock, AsyncMock
from app.core.events import EventBus

@pytest.mark.asyncio
async def test_event_bus_broadcast_with_full_queues():
    """Test that EventBus correctly identifies and removes full subscriber queues."""
    EventBus._subscribers = []
    normal_queue = asyncio.Queue(maxsize=10)
    full_queue = asyncio.Queue(maxsize=1)
    full_queue.put_nowait({"old": "data"})
    EventBus._subscribers.extend([normal_queue, full_queue])
    
    with patch("app.core.events.EventBus._persist_outbox_event", AsyncMock(return_value=123)):
        await EventBus.publish("test_event", {"val": 1})
        
    assert len(EventBus._subscribers) == 1
    assert EventBus._subscribers[0] == normal_queue

@pytest.mark.asyncio
async def test_event_bus_subscribe_timeout_heartbeat():
    """Test that subscribe() yields a ping event on timeout."""
    mock_settings = MagicMock()
    mock_settings.max_sse_subscribers = 5
    with patch("app.core.config.settings", mock_settings):
        with patch("asyncio.wait_for", side_effect=asyncio.TimeoutError):
            gen = EventBus.subscribe()
            async for item in gen:
                assert item["event"] == "ping"
                break

@pytest.mark.asyncio
async def test_event_bus_replay_invalid_payload():
    """Test that replay handles malformed JSON payload by skipping it."""
    # Mocking database response with one valid and one invalid JSON
    mock_rows = [
        (1, "type1", '{"valid": true}'),
        (2, "type2", '{invalid_json}') 
    ]
    mock_result = MagicMock()
    mock_result.fetchall.return_value = mock_rows
    
    with patch("app.core.events.AsyncSessionLocal") as mock_session_factory:
        mock_session = AsyncMock()
        mock_session.execute.return_value = mock_result
        mock_session_factory.return_value.__aenter__.return_value = mock_session
        
        events = await EventBus.replay_events_since(0)
        assert len(events) == 1
        assert events[0]["id"] == 1
        assert events[0]["data"]["valid"] is True

@pytest.mark.asyncio
async def test_event_bus_poll_loop_error_recovery():
    """Test that poll loop continues after a database error."""
    EventBus._running = True
    EventBus._last_seen_event_id = 0
    
    with patch("app.core.events.AsyncSessionLocal") as mock_session_factory:
        mock_session = AsyncMock()
        # First call raises error, second call returns empty list to break/continue
        mock_session.execute.side_effect = [Exception("DB Crash"), MagicMock(fetchall=lambda: [])]
        mock_session_factory.return_value.__aenter__.return_value = mock_session
        
        # We manually run one iteration of the loop logic by calling the method 
        # but mocking sleep to exit or just testing the try-except block
        with patch("asyncio.sleep", side_effect=[None, asyncio.CancelledError]):
            with pytest.raises(asyncio.CancelledError):
                await EventBus._poll_remote_events()
        
        # First call raised Exception, second call returned empty list,
        # then asyncio.sleep was called twice (once for error recovery, once for normal interval)
        assert mock_session.execute.call_count == 2
