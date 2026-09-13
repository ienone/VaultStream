from unittest.mock import AsyncMock
import pytest
from langchain_core.messages import AIMessage
from app.models import Content, Platform
from app.models.media import MediaAsset, MediaType, MediaRole
from app.services.agent.service import _model_with_step_limit
from app.services.agent.tool_registry import AgentToolContext, AgentToolError
from app.services.agent.tools.reading import read_content

async def test_reader_reaches_late_subtitles_and_excludes_foreign_assets(db_session):
    content = Content(url='https://example.com/late-subtitles', platform=Platform.UNIVERSAL, body='视频介绍')
    other = Content(url='https://example.com/foreign-subtitles', platform=Platform.UNIVERSAL)
    db_session.add_all([content, other]);await db_session.flush()
    own = MediaAsset(content_id=content.id, media_type=MediaType.VIDEO, role=MediaRole.ATTACHMENT, duration_ms=1000000)
    foreign = MediaAsset(content_id=other.id, media_type=MediaType.VIDEO, role=MediaRole.ATTACHMENT)
    db_session.add_all([own, foreign]);await db_session.flush()
    content.rich_payload = {'chunks': [
        {'segment_type': 'transcript', 'media_asset_id': own.id, 'start_seconds': i * 30,
         'end_seconds': (i+1)*30, 'content': f'字幕原文{i}', 'generated': True} for i in range(30)] +
        [{'segment_type': 'transcript', 'media_asset_id': foreign.id, 'start_seconds': 750, 'content': '不应出现'}]}
    await db_session.flush()
    result = await read_content({'content_id': content.id, 'start_seconds': 750, 'end_seconds': 780}, AgentToolContext(db=db_session))
    assert len(result['segments']) == 1
    assert result['segments'][0]['text'] == '字幕原文25'
    assert result['segments'][0]['generated'] is True
    assert result['segments'][0]['route'] == f'/collection/{content.id}?t=750&media_asset={own.id}'

async def test_exhausted_tool_budget_is_structured_failure():
    class Model:
        def bind_tools(self, tools): return self
        ainvoke = AsyncMock(return_value=AIMessage(content='', tool_calls=[{'id': 'call', 'name': 'read_content', 'args': {'content_id': 1}}]))
    runnable = _model_with_step_limit(Model(), [])({'remaining_steps': 1}, None)
    with pytest.raises(AgentToolError) as exc:
        await runnable.ainvoke([])
    assert exc.value.error_code == 'agent_step_limit_reached'
