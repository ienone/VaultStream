"""Invalid model ratings must not hide candidates or report batch success."""
import asyncio
import pytest
from types import SimpleNamespace

from sqlalchemy import select

from app.core.llm_factory import LLMFactory
from app.models import Content, Platform, ContentStatus, DiscoveryState, BackgroundTaskRun
from app.services.patrol_service import PatrolScore, PatrolService
from app.core.db_adapter import AsyncSessionLocal
from app.models.search import ContentEmbedding


async def test_invalid_patrol_preserves_candidate_and_fails_batch(db_session, monkeypatch):
    content = Content(url='capture://patrol-invalid', platform=Platform.UNIVERSAL,
                      status=ContentStatus.PARSE_SUCCESS, discovery_state=DiscoveryState.INGESTED,
                      body='Original evidence', summary='Existing summary')
    db_session.add(content)
    await db_session.commit()
    async def invoke(messages):
        return PatrolScore(score=99, reason='invalid', tags=[])
    async def model():
        return SimpleNamespace(with_structured_output=lambda *args, **kwargs: SimpleNamespace(ainvoke=invoke))
    monkeypatch.setattr(LLMFactory,'get_text_llm',model)
    service=PatrolService()
    assert await service.score_pending(db_session)==0
    await db_session.refresh(content)
    assert content.discovery_state==DiscoveryState.INGESTED
    assert content.summary=='Existing summary' and content.body=='Original evidence'
    assert content.ai_score is None
    runs=list(await db_session.scalars(select(BackgroundTaskRun).where(BackgroundTaskRun.task=='discovery_patrol')))
    assert runs[-1].status=='error'


async def test_delayed_patrol_does_not_undo_snooze(client, db_session, monkeypatch):
    content = Content(url='capture://patrol-race', platform=Platform.UNIVERSAL,
                      status=ContentStatus.PARSE_SUCCESS, discovery_state=DiscoveryState.INGESTED,
                      body='Original evidence', summary='Keep this summary')
    db_session.add(content)
    await db_session.commit()
    content_id=content.id
    entered,release=asyncio.Event(),asyncio.Event()
    async def invoke(messages):
        entered.set()
        await release.wait()
        return PatrolScore(score=9, reason='important', tags=[])
    async def model():
        return SimpleNamespace(with_structured_output=lambda *args, **kwargs: SimpleNamespace(ainvoke=invoke))
    monkeypatch.setattr(LLMFactory,'get_text_llm',model)
    job=asyncio.create_task(client.post(f'/api/v1/contents/{content_id}/patrol-score'))
    try:
        await asyncio.wait_for(entered.wait(),5)
        async with AsyncSessionLocal() as writer:
            current=await writer.get(Content,content_id)
            current.discovery_state=DiscoveryState.SNOOZED
            await writer.commit()
    finally:
        release.set()
    response=await job
    assert response.status_code==409
    await db_session.refresh(content)
    assert content.discovery_state==DiscoveryState.SNOOZED
    assert content.summary=='Keep this summary' and content.ai_score is None


@pytest.mark.parametrize('summary', [None, 'Existing full-document summary'])
async def test_successful_patrol_preserves_summary_and_index(db_session, monkeypatch, summary):
    content=Content(url=f'capture://patrol-success/{bool(summary)}',platform=Platform.UNIVERSAL,
                    status=ContentStatus.PARSE_SUCCESS,discovery_state=DiscoveryState.INGESTED,
                    body='Original source',summary=summary,rich_payload={'chunks':[{'content':'Original chunk'}]})
    db_session.add(content)
    await db_session.flush()
    db_session.add(ContentEmbedding(content_id=content.id,source_text='Current evidence'))
    await db_session.commit()
    async def invoke(messages):
        return PatrolScore(score=8, reason='relevant', tags=['python'])
    async def model():
        return SimpleNamespace(with_structured_output=lambda *args, **kwargs: SimpleNamespace(ainvoke=invoke))
    monkeypatch.setattr(LLMFactory,'get_text_llm',model)
    assert await PatrolService().score_item(content,db=db_session)
    await db_session.refresh(content)
    assert content.ai_score==8 and content.discovery_state==DiscoveryState.VISIBLE
    assert content.summary==summary and content.body=='Original source'
    assert content.rich_payload['chunks'][0]['content']=='Original chunk'
    assert await db_session.scalar(select(ContentEmbedding.source_text).where(ContentEmbedding.content_id==content.id))=='Current evidence'


async def test_provider_failure_stops_batch_and_expired_items_are_not_scored(db_session, monkeypatch):
    from datetime import timedelta
    from app.core.time_utils import utcnow
    calls = []
    expired = Content(url='capture://expired-patrol', platform=Platform.UNIVERSAL,
                      discovery_state=DiscoveryState.INGESTED, expire_at=utcnow()-timedelta(days=1))
    items = [Content(url=f'capture://pending-patrol-{i}', platform=Platform.UNIVERSAL,
                     discovery_state=DiscoveryState.INGESTED) for i in range(3)]
    db_session.add_all([expired, *items])
    await db_session.commit()
    async def fail(item, **kwargs):
        calls.append(item.id)
        return False
    service = PatrolService()
    selected = []
    score_batch = service.score_batch
    async def batch(candidates, **kwargs):
        selected.extend(item.id for item in candidates)
        return await score_batch(candidates, **kwargs)
    monkeypatch.setattr(service, 'score_item', fail)
    monkeypatch.setattr(service, 'score_batch', batch)
    assert await service.score_pending(db_session) == 0
    assert len(calls) == 1
    assert expired.id not in selected
    assert {item.id for item in items}.issubset(selected)
