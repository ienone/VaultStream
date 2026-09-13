"""A subscription watermark must not jump across missed pages or failed items."""

import httpx
import pytest

from app.adapters.discovery.telegram import TelegramDiscoveryScraper


def history(ids, before=None):
    messages = ''.join(
        f'<div class="tgme_widget_message_wrap"><div class="tgme_widget_message" '
        f'data-post="TestFeed/{number}"><div class="js-message_text">Message {number}</div>'
        '</div></div>' for number in ids
    )
    link = f'<a class="tme_messages_more" data-before="{before}"></a>' if before else ''
    return f'<section class="tgme_channel_history">{link}{messages}</section>'


@pytest.mark.parametrize('second_page_fails', [False, True])
async def test_backlog_crosses_pages_without_skipping_deleted_watermark(monkeypatch, second_page_fails):
    real_client = httpx.AsyncClient
    requested = []

    def respond(request):
        before = request.url.params.get('before')
        requested.append(before)
        if before is None:
            return httpx.Response(200, text=history(range(31, 51), before=31))
        assert before == '31'
        if second_page_fails:
            return httpx.Response(503, text='private upstream body')
        # Saved 20 has been deleted; 19 still establishes the numeric boundary.
        return httpx.Response(200, text=history([19, *range(21, 31)], before=19))

    monkeypatch.setattr(httpx, 'AsyncClient', lambda **kwargs: real_client(
        **kwargs, transport=httpx.MockTransport(respond)))
    scraper = TelegramDiscoveryScraper({'url': 'https://t.me/TestFeed'})
    if second_page_fails:
        with pytest.raises(ValueError, match='频道抓取或解析失败'):
            await scraper.fetch(last_cursor='TestFeed/20')
    else:
        items, cursor = await scraper.fetch(last_cursor='TestFeed/20')
        assert cursor == 'TestFeed/50'
        assert [item.raw_metadata['entry_id'] for item in items] == [f'TestFeed/{i}' for i in range(50, 20, -1)]
    assert requested == [None, '31']
