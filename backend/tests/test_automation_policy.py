"""A user-disabled policy must block the real orchestration entrypoints."""
from unittest.mock import AsyncMock

from app.services.config_service import ConfigService
from app.services.automation_policy import AutomationPolicyService
from app.services.post_ingest import PostIngestService


async def test_disabled_indexing_never_calls_the_model(db_session, monkeypatch):
    await ConfigService().set_value('enable_auto_semantic_indexing', False)
    index = AsyncMock(side_effect=AssertionError('disabled model was called'))
    monkeypatch.setattr('app.services.embedding_service.EmbeddingService.index_content', index)
    await PostIngestService().schedule_embedding_index(42, source='regression')
    index.assert_not_awaited()


async def test_paused_distribution_blocks_agent_after_confirmation(client, db_session):
    await ConfigService().set_value('distribution_mode', 'paused')
    pending = await client.post('/api/v1/agent/tools/push_batch/invoke', json={
        'args': {'content_ids': [987654321]},
    })
    assert pending.status_code == 200
    confirmation = pending.json()['confirmation']['id']
    response = await client.post(f'/api/v1/agent/confirmations/{confirmation}/decide',
                                 json={'approved': True})
    assert response.status_code == 400
    assert response.json()['error_code'] == 'distribution_paused'


async def test_disabled_favorites_requires_explicit_override(db_session):
    await ConfigService().set_value('allow_manual_favorites_sync_disabled_platform', False)
    policy = AutomationPolicyService(ConfigService())
    assert not (await policy.favorites_platform_manual('zhihu', enabled_platforms=[])).allowed
    assert (await policy.favorites_platform_manual('zhihu', enabled_platforms=[], force=True)).allowed
