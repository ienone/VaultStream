from unittest.mock import AsyncMock
from app.services.content_service import ContentService


async def test_first_page_aliases_merge_but_other_pages_stay_separate(db_session, monkeypatch):
    monkeypatch.setattr('app.services.content_service.task_queue.enqueue', AsyncMock(return_value=True))
    service = ContentService(db_session)
    base='https://www.bilibili.com/video/BV1z2421P7wV'
    first=await service.create_share(base, source_name='manual_paste')
    cid=first.id
    same=await service.create_share(base+'/?p=1&spm_id_from=test', source_name='system_share')
    assert same.id == cid
    second=await service.create_share(base+'?p=2', source_name='manual_paste')
    assert second.id != cid
    same_second=await service.create_share(base+'/?p=02', source_name='system_share')
    assert same_second.id == second.id


async def test_invalid_video_page_does_not_silently_select_first_page():
    import pytest
    from app.adapters.bilibili import BilibiliAdapter
    from app.adapters.errors import NonRetryableAdapterError
    for page in ['', '0', '-1', 'abc']:
        with pytest.raises(NonRetryableAdapterError):
            await BilibiliAdapter().clean_url('https://www.bilibili.com/video/BV1z2421P7wV?p='+page)
