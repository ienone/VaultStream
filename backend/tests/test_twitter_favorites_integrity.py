"""X timeline parsing and session-bound resume cannot silently drop a page."""
import json
from unittest.mock import AsyncMock

import pytest

from app.adapters.favorites.twitter_fetcher import TwitterBookmarksFetcher, parse_bookmarks
from app.adapters.favorites.errors import FavoritesFetchError
from app.services.config_service import ConfigService


def timeline(ids, cursor='next-page'):
    entries = [{'content': {'entryType': 'TimelineTimelineItem', 'itemContent': {'tweet_results': {'result': {
        '__typename': 'Tweet', 'rest_id': str(n), 'legacy': {'full_text': f'Bookmark {n}'}}}}}} for n in ids]
    if cursor:
        entries.append({'content': {'entryType': 'TimelineTimelineCursor', 'cursorType': 'Bottom', 'value': cursor}})
    return {'data': {'bookmark_timeline_v2': {'timeline': {'instructions': [{'type': 'TimelineAddEntries', 'entries': entries}]}}}}


async def test_resume_page_offset_and_session_replacement(monkeypatch):
    cookies = {'auth_token': 'fixture-auth', 'ct0': 'fixture-csrf'}
    fetcher = TwitterBookmarksFetcher()
    monkeypatch.setattr(fetcher, '_cookies', AsyncMock(return_value=cookies))
    read = AsyncMock(return_value=(timeline([101, 102, 103]), cookies))
    monkeypatch.setattr(fetcher, '_read_page', read)
    first, cursor = await fetcher.fetch_favorites(max_items=2)
    rest, next_cursor = await fetcher.fetch_favorites(max_items=10, cursor=cursor)
    assert [item.item_id for item in first + rest] == ['101', '102', '103']
    assert json.loads(next_cursor)['cursor'] == 'next-page'
    assert all(call.args[1] is None for call in read.await_args_list)
    monkeypatch.setattr(fetcher, '_cookies', AsyncMock(return_value={**cookies, 'auth_token': 'new-login'}))
    with pytest.raises(FavoritesFetchError) as error:
        await fetcher.fetch_favorites(cursor=next_cursor)
    assert error.value.code == 'invalid_cursor'
    assert read.await_count == 2


@pytest.mark.parametrize('payload', [{}, {'errors': [{'code': 89}]}, timeline([101], cursor=None)])
def test_invalid_or_failed_response_is_not_empty_success(payload):
    with pytest.raises(FavoritesFetchError):
        parse_bookmarks(payload)


async def test_x_cookie_is_masked_in_settings_api(client):
    cfg = ConfigService()
    try:
        await cfg.set_value('twitter_cookie', 'auth_token=fixture-private; ct0=fixture-csrf')
        response = await client.get('/api/v1/settings/twitter_cookie')
        assert response.status_code == 200
        assert 'fixture-private' not in response.text and 'fixture-csrf' not in response.text
    finally:
        await cfg.delete_value('twitter_cookie')
