import pytest
from unittest.mock import MagicMock, AsyncMock, patch
from app.tasks.parsing import ContentParser
from app.models import Content, ContentStatus, Platform
from app.adapters.base import ParsedContent
from sqlalchemy import select

@pytest.fixture(autouse=True)
def mock_event_bus():
    with patch("app.core.events.event_bus.publish", new_callable=AsyncMock) as mock:
        yield mock

@pytest.mark.asyncio
async def test_process_parse_task_success(db_session, monkeypatch):
    # 1. Setup test data in DB
    content = Content(
        url="https://www.bilibili.com/video/BV1GJ411x7h7",
        platform=Platform.BILIBILI,
        status=ContentStatus.UNPROCESSED
    )
    db_session.add(content)
    await db_session.commit()
    await db_session.refresh(content)
    content_id = content.id

    # 2. Mock Adapter and Factory
    mock_parsed = ParsedContent(
        platform="bilibili",
        content_type="video",
        content_id="BV1GJ411x7h7",
        clean_url="https://www.bilibili.com/video/BV1GJ411x7h7",
        title="Mock Title",
        body="Mock Body",
        author_name="Mock Author",
        layout_type="gallery"
    )
    
    mock_adapter = AsyncMock()
    mock_adapter.parse.return_value = mock_parsed
    
    # 3. Patch dependencies
    # We need to monkeypatch AsyncSessionLocal used inside ContentParser
    from tests.conftest import TestingSessionLocal
    monkeypatch.setattr("app.tasks.parsing.AsyncSessionLocal", TestingSessionLocal)
    
    # Mock AdapterFactory
    with patch("app.tasks.parsing.AdapterFactory.create", return_value=mock_adapter), \
         patch("app.tasks.parsing.task_queue.mark_complete", new_callable=AsyncMock) as mock_mark_complete:
        
        parser = ContentParser()
        task_data = {"content_id": content_id, "action": "parse"}
        
        # 4. Execute
        await parser.process_parse_task(task_data, "test_task_id")
        
        # 5. Verify
        await db_session.refresh(content)
        assert content.status == ContentStatus.PARSE_SUCCESS
        assert content.title == "Mock Title"
        assert content.author_name == "Mock Author"
        mock_mark_complete.assert_called_once_with(content_id)

@pytest.mark.asyncio
async def test_process_parse_task_failure(db_session, monkeypatch):
    # 1. Setup test data
    content = Content(
        url="https://www.bilibili.com/video/invalid",
        platform=Platform.BILIBILI,
        status=ContentStatus.UNPROCESSED
    )
    db_session.add(content)
    await db_session.commit()
    await db_session.refresh(content)
    content_id = content.id

    # 2. Patch dependencies
    from tests.conftest import TestingSessionLocal
    monkeypatch.setattr("app.tasks.parsing.AsyncSessionLocal", TestingSessionLocal)
    
    with patch("app.tasks.parsing.AdapterFactory.create") as mock_factory, \
         patch("app.tasks.parsing.task_queue.mark_complete", new_callable=AsyncMock):
        
        mock_adapter = AsyncMock()
        mock_adapter.parse.side_effect = Exception("Parse error")
        mock_factory.return_value = mock_adapter
        
        parser = ContentParser()
        task_data = {"content_id": content_id, "action": "parse", "max_attempts": 1}
        
        # 3. Execute
        await parser.process_parse_task(task_data, "test_task_id")
        
        # 4. Verify
        await db_session.refresh(content)
        assert content.status == ContentStatus.PARSE_FAILED
        assert "Parse error" in content.last_error_detail["message"]
