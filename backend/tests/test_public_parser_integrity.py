"""Public parsing must not mix object identities or archive incomplete bodies."""
import json
from unittest.mock import AsyncMock

import httpx
import pytest
import requests

from app.adapters.errors import NonRetryableAdapterError, RetryableAdapterError
from app.adapters.zhihu import ZhihuAdapter
from app.adapters.zhihu_parser.article_parser import parse_article
from app.adapters.zhihu_parser.question_parser import parse_question
from app.adapters.zhihu_parser.people_parser import parse_people
from app.adapters.zhihu_parser.public_reader import parse_public_reader
from app.adapters.xiaohongshu_parser.note_parser import extract_ssr_note, fetch_note, parse_note
from app.adapters.xiaohongshu_parser.user_parser import extract_ssr_user
from app.adapters.weibo_parser.weibo_parser import _parse_weibo_sync
from app.adapters.utils import tiered_fetcher
from app.adapters.utils.content_agent import process_content
from app.core.safe_fetch import SafeFetchResult


def reader_html(**overrides):
    render = {
        'type': 'ans', 'title': '公开问题', 'question_token': '12345',
        'deeplink_url': 'https://oia.zhihu.com/question/67890',
        'content': '<p>完整正文</p><img src="https://pic.zhimg.com/content.jpg">',
        'author': {'name': '作者', 'logo': 'https://pic.zhimg.com/avatar.jpg'},
        'created': 1752530795, 'upvoted_count': 12, 'comment_count': 3,
        'favorites': 4, 'answer_count': 9,
    }
    render.update(overrides)
    return '<script>window.g_initialProps = ' + json.dumps({'renderHtml': render}) + '; window.unrelated = 1;</script>'


@pytest.mark.parametrize('overrides', [
    {'deeplink_url': 'https://oia.zhihu.com/question/77777'},
    {'question_token': '99999'}, {'type': 'art'}, {'content': ''},
])
def test_reader_rejects_wrong_object_or_missing_body(overrides):
    assert parse_public_reader(reader_html(**overrides),
        'https://www.zhihu.com/question/12345/answer/67890', 'answer', '67890') is None


async def test_anonymous_reader_preserves_body_without_login_or_fake_publish_time(monkeypatch):
    url = 'https://www.zhihu.com/question/12345/answer/67890'
    reader = 'https://www.zhihu.com/tardis/zm/ans/67890'
    adapter = ZhihuAdapter()
    adapter.cookies = {}
    adapter.raw_cookie_str = None
    monkeypatch.setattr(adapter, '_get_proxy_url', AsyncMock(return_value=None))
    api = AsyncMock(side_effect=AssertionError('anonymous reader must not call API'))
    monkeypatch.setattr(adapter, '_api_request', api)
    async def get(client, target, **kwargs):
        assert target == reader
        assert not client.cookies and 'cookie' not in kwargs['headers']
        return SafeFetchResult(reader, 200, httpx.Headers({'content-type':'text/html'}), reader_html().encode())
    monkeypatch.setattr('app.adapters.zhihu.safe_client_get', get)
    parsed = await adapter.parse(url)
    assert '完整正文' in parsed.body
    assert parsed.media_urls == ['https://pic.zhimg.com/content.jpg']
    assert parsed.published_at is None and parsed.author_id is None
    assert parsed.stats['favorite'] == 4
    assert parsed.context_data['id'] == '12345'
    api.assert_not_called()


def test_zhihu_article_never_substitutes_a_recommendation():
    html = '<script id="js-initialData">' + json.dumps({'initialState': {'entities': {
        'articles': {'99999': {'id':'99999', 'title':'Other', 'content':'<p>Other body</p>'}}
    }}}) + '</script>'
    assert parse_article(html, 'https://zhuanlan.zhihu.com/p/12345') is None


def test_zhihu_question_and_profile_check_payload_identity():
    def page(entities):
        return '<script id="js-initialData">' + json.dumps({'initialState': {'entities': entities}}) + '</script>'
    assert parse_question(page({'questions': {'12345': {'id': '99999', 'title': 'Other'}}}),
                          'https://www.zhihu.com/question/12345') is None
    assert parse_people(page({'users': {'target': {'urlToken': 'other', 'name': 'Other'}}}),
                        'https://www.zhihu.com/people/target') is None
    parsed = parse_people(page({'users': {'target': {'urlToken': 'target', 'id': '12345', 'name': 'User'}}}),
                          'https://www.zhihu.com/people/target')
    assert parsed.author_id == 'target' and parsed.published_at is None


@pytest.mark.parametrize('kind,url', [
    ('article', 'https://zhuanlan.zhihu.com/p/12345'),
    ('question', 'https://www.zhihu.com/question/12345'),
    ('user_profile', 'https://www.zhihu.com/people/12345'),
])
async def test_zhihu_public_pages_do_not_require_an_account_api(monkeypatch, kind, url):
    adapter = ZhihuAdapter()
    adapter.cookies = {}
    monkeypatch.setattr(adapter, '_get_proxy_url', AsyncMock(return_value=None))
    monkeypatch.setattr(adapter, '_parse_public_reader', AsyncMock(return_value=None))
    api = AsyncMock(side_effect=AssertionError('public pages must not depend on account API'))
    monkeypatch.setattr(adapter, '_api_request', api)
    from app.adapters.base import ParsedContent
    result = ParsedContent(platform='zhihu', content_type=kind, content_id='12345', clean_url=url, title='Target', layout_type='article')
    browser = AsyncMock(return_value=result)
    monkeypatch.setattr('app.adapters.zhihu.read_public_page', browser)
    assert await adapter.parse(url) is result
    browser.assert_awaited_once_with(kind, '12345', None)
    api.assert_not_called()


def test_xhs_preserves_literal_undefined_and_matches_note_identity():
    note = {'noteId':'target', 'desc':'literal :undefined,undefined', 'imageList':[]}
    state = json.dumps({'note':{'noteDetailMap':{'target':{'note':note}}}})
    html = '<script>window.__INITIAL_STATE__=' + state[:-1] + ',"unused":undefined};</script>'
    assert extract_ssr_note(html, 'target')['desc'] == note['desc']
    with pytest.raises(NonRetryableAdapterError):
        extract_ssr_note(html, 'other')
    note['noteId'] = 'other'
    html = '<script>window.__INITIAL_STATE__=' + json.dumps({'note':{'noteDetailMap':{'target':{'note':note}}}}) + '</script>'
    with pytest.raises(NonRetryableAdapterError):
        extract_ssr_note(html, 'target')


def test_xhs_profile_rejects_wrong_identity_and_failed_profile_state():
    user = {'userFetchingStatus': 'resolved', 'noteQueries': [{'userId': 'target'}],
            'userPageData': {'result': {'success': True, 'code': 0},
                             'basicInfo': {'nickname': 'literal new Set([]) undefined'}}}
    def page():
        return '<script>window.__INITIAL_STATE__=' + json.dumps({'user': user})[:-1] + ',"selection":new Set([])};</script>'
    assert extract_ssr_user(page(), 'target')['basicInfo']['nickname'] == 'literal new Set([]) undefined'
    with pytest.raises(NonRetryableAdapterError):
        extract_ssr_user(page(), 'other')
    user['userPageData']['result']['success'] = False
    with pytest.raises(NonRetryableAdapterError):
        extract_ssr_user(page(), 'target')


async def test_xhs_shared_link_does_not_require_signed_api(monkeypatch):
    ssr = AsyncMock(return_value={'note_id':'target', 'desc':'public'})
    api = AsyncMock(side_effect=AssertionError('no account'))
    monkeypatch.setattr('app.adapters.xiaohongshu_parser.note_parser.fetch_note_via_ssr', ssr)
    monkeypatch.setattr('app.adapters.xiaohongshu_parser.note_parser.fetch_note_via_api', api)
    result = await fetch_note('target', None, {}, {}, 'share-token')
    assert result['note_id'] == 'target'
    api.assert_not_called()
    assert ssr.call_args.args[1] == {}


async def test_xhs_ssr_preserves_author_video_and_excludes_avatar(monkeypatch):
    note = {
        'noteId': 'target', 'title': 'Video', 'type': 'video', 'desc': 'Original body',
        'user': {'userId': 'author', 'nickname': 'Author', 'avatar': 'https://example.org/avatar.jpg'},
        'imageList': [{'urlDefault': 'https://example.org/cover.jpg'}],
        'video': {'media': {'stream': {'h264': [{
            'masterUrl': 'https://example.org/video.mp4', 'width': 720, 'height': 1080,
            'duration': 463367,
        }]}}},
    }
    html = '<script>window.__INITIAL_STATE__=' + json.dumps({'note': {'noteDetailMap': {'target': {'note': note}}}}) + '</script>'
    monkeypatch.setattr('app.adapters.xiaohongshu_parser.note_parser.fetch_note_via_ssr',
                        AsyncMock(return_value=extract_ssr_note(html, 'target')))
    parsed = await parse_note('target', 'https://www.xiaohongshu.com/explore/target', None, {}, {}, 'token')
    assert parsed.author_id == 'author'
    assert parsed.layout_type == 'video'
    assert parsed.media_urls == ['https://example.org/cover.jpg', 'https://example.org/video.mp4']
    video = parsed.archive_metadata['archive']['videos'][0]
    assert (video['width'], video['height'], video['duration']) == (720, 1080, 463.367)


@pytest.mark.parametrize('long_response', [None, {}, {'data': {'longTextContent': ''}}])
def test_weibo_long_text_failure_never_saves_excerpt(monkeypatch, long_response):
    proxies = {'https': 'http://proxy.invalid:7890'}
    calls = []
    def get(url, **kwargs):
        calls.append(url)
        assert kwargs['proxies'] == proxies
        if '/longtext?' in url and long_response is None:
            raise requests.Timeout()
        response = requests.Response()
        response.status_code = 200
        response._content = json.dumps(
            {'ok':1, 'text':'truncated excerpt', 'isLongText':True}
            if '/show?' in url else long_response
        ).encode()
        return response
    monkeypatch.setattr(requests, 'get', get)
    with pytest.raises(RetryableAdapterError, match='长文'):
        _parse_weibo_sync('12345', 'https://weibo.com/detail/12345', {}, {}, proxies)
    assert len(calls) == 2


async def test_http_html_is_reused_and_structured_body_needs_no_model(monkeypatch):
    html = '''<meta property="og:title" content="Article">
      <article itemscope itemtype="https://schema.org/Article">
      <h1 itemprop="headline">Article</h1><div itemprop="articleBody">
      <p>First paragraph with enough readable material to pass the page check.</p>
      <p>Second paragraph with an <a href="/source">original source</a> and retained end marker.</p>
      <img src="/photo.jpg"></div></article>'''
    async def get(client, url, **kwargs):
        return SafeFetchResult('https://example.org/posts/1', 200,
            httpx.Headers({'content-type':'text/html'}), html.encode())
    getter = AsyncMock(side_effect=get)
    browser = AsyncMock(side_effect=AssertionError('HTML already fetched'))
    monkeypatch.setattr(tiered_fetcher, 'safe_client_get', getter)
    monkeypatch.setattr(tiered_fetcher, '_try_browser', browser)
    monkeypatch.setattr('app.adapters.utils.content_agent._content_llm',
        lambda _: pytest.fail('semantic content must not call a model'))
    fetched = await tiered_fetcher.tiered_fetch('https://example.org/redirect')
    result = await process_content(fetched.url, fetched, None)
    assert result.llm_calls == 0
    assert 'retained end marker' in result.cleaned_markdown
    assert 'https://example.org/photo.jpg' in result.cleaned_markdown
    assert 'https://example.org/source' in result.cleaned_markdown
    assert getter.await_count == 1
    browser.assert_not_called()


@pytest.mark.parametrize('status', [404, 410, 429])
async def test_terminal_http_errors_do_not_launch_browser(monkeypatch, status):
    async def get(*args, **kwargs):
        return SafeFetchResult('https://example.org/gone', status,
            httpx.Headers({'content-type':'text/html'}), b'Gone')
    monkeypatch.setattr(tiered_fetcher, 'safe_client_get', get)
    browser = AsyncMock(side_effect=AssertionError('terminal response'))
    monkeypatch.setattr(tiered_fetcher, '_try_browser', browser)
    with pytest.raises((NonRetryableAdapterError, RetryableAdapterError)):
        await tiered_fetcher.tiered_fetch('https://example.org/gone')
    browser.assert_not_called()


def test_long_challenge_page_is_not_readable_content():
    html = '<title>Sina Visitor System</title><article>' + ('verification ' * 100) + '</article>'
    assert not tiered_fetcher._has_sufficient_content(html)
    # "Design in ..." is an article title, not a "sign in" page.
    article = html.replace('Sina Visitor System', 'Design in practice')
    assert tiered_fetcher._has_sufficient_content(article)
