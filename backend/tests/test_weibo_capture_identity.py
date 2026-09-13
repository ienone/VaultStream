from unittest.mock import AsyncMock
from sqlalchemy import func, select
from app.models import ContentSource
from app.services.content_service import ContentService
from app.adapters.weibo import WeiboAdapter


async def test_numeric_and_short_links_share_one_content(db_session, monkeypatch):
    monkeypatch.setattr('app.services.content_service.task_queue.enqueue', AsyncMock(return_value=True))
    service = ContentService(db_session)
    first = await service.create_share('https://weibo.com/2/detail/5331437486081232', source_name='manual_paste')
    cid = first.id
    second = await service.create_share('https://weibo.com/detail/RdbPCpw0o', source_name='clipboard')
    assert second.id == cid
    assert second.canonical_url == 'https://weibo.com/detail/5331437486081232'
    assert await db_session.scalar(select(func.count()).select_from(ContentSource).where(ContentSource.content_id == cid)) == 2
    adapter = WeiboAdapter()
    assert await adapter.clean_url('https://weibo.com/123456/RdbPCpw0o') == second.canonical_url
    assert await adapter.clean_url('https://weibo.com/u/2803301701') == 'https://weibo.com/u/2803301701'
