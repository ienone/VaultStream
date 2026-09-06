import asyncio
from datetime import timedelta
from uuid import uuid4
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.time_utils import utcnow
from app.core.db_adapter import AsyncSessionLocal
from app.models import Content, ContentStatus, Platform
from app.schemas.knowledge_event import KnowledgeEventCreate
from app.services.content_service import ContentService
from app.services.knowledge_event_service import KnowledgeEventError, KnowledgeEventService


async def _content(
    db: AsyncSession,
    *,
    url: str,
    title: str,
    published_offset: int,
) -> Content:
    now = utcnow()
    item = Content(
        platform=Platform.UNIVERSAL,
        url=url,
        canonical_url=url,
        status=ContentStatus.PARSE_SUCCESS,
        title=title,
        body=f"{title} 的来源正文",
        created_at=now,
        updated_at=now,
        published_at=now + timedelta(hours=published_offset),
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return item


async def test_content_delete_and_member_removal_share_last_member_guard(client, db_session):
    content = await _content(db_session, url=f'https://example.test/{uuid4().hex}',
                             title='唯一来源', published_offset=0)
    response = await client.post('/api/v1/knowledge-events', json={
        'title': '保留证据', 'members': [{'content_id': content.id}],
    })
    assert response.status_code == 201
    event_id = response.json()['id']
    for path in (f'/api/v1/contents/{content.id}',
                 f'/api/v1/knowledge-events/{event_id}/members/{content.id}'):
        deleted = await client.delete(path)
        assert deleted.status_code == 409
        assert deleted.json()['error_code'] == 'knowledge_event_requires_member'
    assert (await client.get(f'/api/v1/knowledge-events/{event_id}')).json()['member_count'] == 1
    assert (await client.get(f'/api/v1/contents/{content.id}')).status_code == 200


async def test_concurrent_content_deletes_cannot_leave_an_empty_event(db_session):
    items = [await _content(db_session, url=f'https://example.test/{uuid4().hex}',
                            title='来源', published_offset=index) for index in range(2)]
    async with AsyncSessionLocal() as db:
        event = await KnowledgeEventService(db).create_event(KnowledgeEventCreate(
            title='并发删除', members=[{'content_id': item.id} for item in items],
        ))

    async def remove(content_id):
        async with AsyncSessionLocal() as db:
            try:
                await ContentService(db).delete_content(content_id)
                return 'deleted'
            except KnowledgeEventError as error:
                await db.rollback()
                return error.code

    outcomes = await asyncio.gather(*(remove(item.id) for item in items))
    assert sorted(outcomes) == ['deleted', 'knowledge_event_requires_member']
    async with AsyncSessionLocal() as db:
        detail = await KnowledgeEventService(db).get_event(event['id'])
        assert detail['member_count'] == 1
        assert await db.get(Content, detail['members'][0]['content_id']) is not None
