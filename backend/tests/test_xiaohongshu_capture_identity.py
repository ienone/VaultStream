"""A refreshed note access token must not create a second archived item."""
from unittest.mock import AsyncMock

from sqlalchemy import func, select

from app.adapters.xiaohongshu import XiaohongshuAdapter
from app.models import ContentSource
from app.services.content_service import ContentService


async def test_note_token_refresh_reuses_content_and_preserves_parse_url(db_session, monkeypatch):
    monkeypatch.setattr('app.services.content_service.task_queue.enqueue', AsyncMock(return_value=True))
    service = ContentService(db_session)
    base = 'https://www.xiaohongshu.com/explore/6a462e8e000000000f007c93'
    first = await service.create_share(base + '?xsec_token=first-fixture', source_name='manual_paste')
    first_id = first.id
    second = await service.create_share(base + '?xsec_token=second-fixture', source_name='favorites_sync:xiaohongshu')
    assert second.id == first_id
    assert second.canonical_url == base
    assert XiaohongshuAdapter()._extract_xsec_token(second.url) == 'second-fixture'
    sources = await db_session.scalar(select(func.count()).select_from(ContentSource).where(ContentSource.content_id == second.id))
    assert sources == 2
