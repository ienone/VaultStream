"""A failed external summary must preserve the old result and fail its receipt."""

from types import SimpleNamespace

import pytest
from google import genai
from sqlalchemy import select

from app.models import Content, Platform, ContentStatus, BackgroundTaskRun
from app.models.search import ContentEmbedding
from app.services import content_summary_service


@pytest.mark.parametrize('failure,status', [('provider', 502), ('configuration', 503), ('empty_result', 502)])
async def test_summary_failure_preserves_existing_result(client, db_session, monkeypatch, failure, status):
    content = Content(url=f'capture://summary-failure/{failure}', platform=Platform.UNIVERSAL,
                      status=ContentStatus.PARSE_SUCCESS, body='Original source', summary='Previous summary',
                      rich_payload={'chunks': [{'title': 'Previous', 'content': 'Previous evidence'}]})
    db_session.add(content)
    await db_session.commit()
    content_id = content.id
    db_session.add(ContentEmbedding(content_id=content_id, source_text='Previous indexed evidence'))
    await db_session.commit()
    async def config():
        return (None if failure == 'configuration' else 'placeholder'), 'test-model', 'v1beta'
    def generate(**kwargs):
        if failure == 'empty_result':
            return SimpleNamespace(parsed={'summary': '', 'tags': [], 'rag_chunks': []})
        raise RuntimeError('sensitive-provider-detail-must-not-leak')
    monkeypatch.setattr(content_summary_service, '_get_summary_llm_config', config)
    monkeypatch.setattr(genai, 'Client', lambda **kwargs: SimpleNamespace(models=SimpleNamespace(generate_content=generate)))
    response = await client.post(f'/api/v1/contents/{content_id}/generate-summary?force=true')
    assert response.status_code == status
    assert 'sensitive-provider-detail' not in response.text
    await db_session.refresh(content)
    assert content.summary == 'Previous summary'
    assert content.rich_payload['chunks'][0]['content'] == 'Previous evidence'
    assert await db_session.scalar(select(ContentEmbedding.source_text).where(ContentEmbedding.content_id == content_id)) == 'Previous indexed evidence'
    runs = list(await db_session.scalars(select(BackgroundTaskRun).where(BackgroundTaskRun.task == 'content_summary')))
    run = next(run for run in runs if run.run_metadata.get('content_id') == content_id)
    assert run.status == 'error'
    assert 'sensitive-provider-detail' not in (run.error or '')
