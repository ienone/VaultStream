from unittest.mock import AsyncMock
import pytest
from app.adapters.favorites.base import FavoriteItem
from app.services.config_service import ConfigService
from app.tasks.favorites_sync import FavoritesSyncTask

@pytest.mark.parametrize('failed', [False, True])
async def test_cursor_clears_at_end_but_does_not_skip_failed_imports(monkeypatch, failed):
    cfg = ConfigService()
    await cfg.set_favorites_sync_cursor('xiaohongshu', 'current-page')
    class Fetcher:
        def platform_name(self): return 'xiaohongshu'
        async def check_auth(self): return True
        async def fetch_favorites(self, **kwargs):
            assert kwargs['cursor'] == 'current-page'
            return ([FavoriteItem(url='https://www.xiaohongshu.com/explore/fixture')] if failed else []), ('next-page' if failed else None)
    task = FavoritesSyncTask()
    monkeypatch.setattr(task, 'default_rate_for', lambda platform: 1e9)
    if failed:
        monkeypatch.setattr('app.services.content_service.ContentService.create_share', AsyncMock(side_effect=RuntimeError('fixture unavailable')))
    result = await task._sync_platform(Fetcher())
    cursor = await cfg.get_value_fresh('favorites_sync_cursor_xiaohongshu')
    assert cursor == ('current-page' if failed else None)
    assert result['next_cursor'] == cursor
    assert result['failed'] == int(failed)
