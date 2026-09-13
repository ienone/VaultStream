"""X web transport: current page client owns its GraphQL protocol and login."""
import json
from urllib.parse import parse_qs, urlencode, urlparse, urlunparse
from playwright.async_api import Error as BrowserError, TimeoutError as BrowserTimeout
from app.adapters.browser import browser_manager
from app.services.config_service import ConfigService


def _error(code, message):
    from app.adapters.favorites.errors import FavoritesFetchError
    return FavoritesFetchError(code=code, message=message,
        hint="请在 X 网页确认登录或访问验证，再更新 VaultStream 登录", auth_required=code == "auth_required",
        retryable=code not in ("auth_required", "verification_required"))


async def read_x_page(cookies, *, cursor=None, tweet_id=None):
    operation = "TweetDetail" if tweet_id is not None else "Bookmarks"
    if tweet_id is not None and (not isinstance(tweet_id, str) or not tweet_id.isdigit()):
        raise ValueError("invalid X tweet ID")
    proxy = await ConfigService().get_http_proxy()
    async def read():
        browser = browser_manager.get_browser()
        options = {"viewport": browser_manager.fetch_viewport}
        if proxy:
            options["proxy"] = {"server": proxy}
        context = await browser.new_context(**options)
        route_error = False
        try:
            await context.add_cookies([{"name": key, "value": value, "domain": ".x.com", "path": "/", "secure": True}
                for key, value in cookies.items()])
            page = await context.new_page()
            async def paginate(route):
                nonlocal route_error
                try:
                    parts = urlparse(route.request.url)
                    query = parse_qs(parts.query)
                    variables = json.loads(query["variables"][0])
                    if route.request.method != "GET" or type(variables["count"]) is not int:
                        raise ValueError
                    variables["count"] = 50
                    if cursor:
                        variables["cursor"] = cursor
                    else:
                        variables.pop("cursor", None)
                    query["variables"] = [json.dumps(variables)]
                    await route.continue_(url=urlunparse(parts._replace(query=urlencode(query, doseq=True))))
                except (KeyError, ValueError, TypeError):
                    route_error = True
                    await route.abort()
            if operation == "Bookmarks":
                await page.route("**/i/api/graphql/*/Bookmarks?*", paginate)
            def matches(response):
                parts = urlparse(response.url)
                return parts.hostname == "x.com" and parts.path.endswith("/" + operation)
            try:
                async with page.expect_response(matches, timeout=30000) as pending:
                    await page.goto(f"https://x.com/i/status/{tweet_id}" if tweet_id else "https://x.com/i/bookmarks", wait_until="domcontentloaded", timeout=30000)
                response = await pending.value
            except BrowserTimeout:
                if route_error:
                    raise _error("parse_failed", "X 网页书签请求结构已变化") from None
                if "/i/flow/login" in page.url:
                    raise _error("auth_required", "X 网页要求重新登录") from None
                raise _error("verification_required", "X 未提供书签响应，请在网页检查登录或访问验证") from None
            if response.status in (401,):
                raise _error("auth_required", "X 登录已失效")
            if response.status in (403, 429):
                raise _error("verification_required", "X 拒绝或限制当前书签访问，请在网页处理")
            if response.status != 200:
                raise _error("upstream_error", f"X 书签返回 HTTP {response.status}")
            try:
                payload = await response.json()
            except (ValueError, BrowserError):
                raise _error("parse_failed", "X 未返回有效书签 JSON") from None
            refreshed = {item["name"]: item["value"] for item in await context.cookies("https://x.com")}
            return payload, refreshed
        finally:
            await context.close()
    try:
        return await browser_manager.submit_coro(read())
    except BrowserError:
        raise _error("browser_unavailable", "X 书签浏览器读取失败，请检查浏览器运行环境和网络") from None


def timeline_instructions(payload, operation):
    """Two published X schema revisions, not a fallback to a different endpoint."""
    if not isinstance(payload, dict) or payload.get('errors'):
        raise _error('upstream_error', 'X 时间线接口返回错误')
    try:
        data = payload['data']
        candidates = []
        if operation == 'Bookmarks':
            for name in ('bookmark_timeline', 'bookmark_timeline_v2'):
                if name in data:
                    candidates.append(data[name]['timeline']['instructions'])
        else:
            if 'tweetResult' in data:
                candidates.append(data['tweetResult']['result']['timeline']['instructions'])
            if 'threaded_conversation_with_injections_v2' in data:
                candidates.append(data['threaded_conversation_with_injections_v2']['instructions'])
        if len(candidates) != 1 or not isinstance(candidates[0], list):
            raise ValueError
        return candidates[0]
    except (KeyError, TypeError, ValueError):
        raise _error('parse_failed', 'X 时间线响应不符合已核对的协议修订') from None


def parse_web_tweet(payload, tweet_id):
    from datetime import datetime
    from html import unescape
    from app.adapters.base import ParsedContent
    try:
        instructions = timeline_instructions(payload, 'TweetDetail')
        entries = [entry for instruction in instructions if instruction.get('type') == 'TimelineAddEntries'
                   for entry in instruction['entries']]
        entry = next((entry for entry in entries if entry.get('entryId') == f'tweet-{tweet_id}'), None)
        if entry is None:
            raise _error('content_unavailable', 'X 未返回目标推文，可能已删除或当前账号无权访问')
        tweet = entry['content']['itemContent']['tweet_results']['result']
        if tweet.get('__typename') == 'TweetWithVisibilityResults':
            tweet = tweet['tweet']
        if tweet.get('__typename') != 'Tweet' or tweet['rest_id'] != tweet_id:
            raise _error('content_unavailable', 'X 未返回可读取的目标推文')
        legacy = tweet['legacy']
        text = legacy['full_text']
        if 'note_tweet' in tweet:
            text = tweet['note_tweet']['note_tweet_results']['result']['text']
        if not isinstance(text, str):
            raise ValueError
        text = unescape(text)
        user = tweet['core']['user_results']['result']
        profile = user['core'] if 'core' in user else user['legacy']
        author_id = user['rest_id']
        images, videos, media_urls = [], [], []
        for media in legacy.get('extended_entities', {}).get('media', []):
            size = media.get('original_info', {})
            if media['type'] == 'photo':
                url = media['media_url_https']
                images.append({'url': url, 'width': size.get('width'), 'height': size.get('height')})
            elif media['type'] in ('video', 'animated_gif'):
                variants = [v for v in media['video_info']['variants'] if v.get('content_type') == 'video/mp4']
                if not variants:
                    raise _error('content_unavailable', 'X 未提供当前视频的可读取流')
                url = max(variants, key=lambda v: v.get('bitrate', 0))['url']
                videos.append({'url': url, 'thumbnail_url': media['media_url_https'],
                    'width': size.get('width'), 'height': size.get('height')})
            else:
                raise ValueError
            media_urls.append(url)
        created = datetime.strptime(legacy['created_at'], '%a %b %d %H:%M:%S %z %Y') if legacy.get('created_at') else None
        avatar = user.get('avatar', {}).get('image_url') or user.get('legacy', {}).get('profile_image_url_https')
        tags = [item['text'] for item in legacy.get('entities', {}).get('hashtags', [])]
        rich = {}
        if 'quoted_status_result' in tweet:
            quoted = tweet['quoted_status_result']['result']
            if quoted.get('__typename') == 'TweetWithVisibilityResults':
                quoted = quoted['tweet']
            if quoted.get('__typename') == 'Tweet':
                quote_user = quoted['core']['user_results']['result']
                quote_profile = quote_user['core'] if 'core' in quote_user else quote_user['legacy']
                quote_text = quoted['legacy']['full_text']
                if 'note_tweet' in quoted:
                    quote_text = quoted['note_tweet']['note_tweet_results']['result']['text']
                rich['quoted_content'] = {'author': quote_profile.get('name'), 'text': unescape(quote_text),
                    'url': f"https://x.com/i/status/{quoted['rest_id']}"}
        return ParsedContent(platform='twitter', content_type='tweet', content_id=tweet_id,
            clean_url=f'https://x.com/i/status/{tweet_id}', layout_type='video' if videos else 'gallery' if images else 'article',
            title=text[:200], body=text, author_name=profile.get('name'), author_id=author_id,
            author_url=f'https://x.com/i/user/{author_id}', author_avatar_url=avatar,
            cover_url=(videos[0]['thumbnail_url'] if videos else images[0]['url'] if images else None),
            media_urls=media_urls, published_at=created, source_tags=tags, rich_payload=rich or None,
            stats={'like': legacy.get('favorite_count', 0), 'share': legacy.get('retweet_count', 0),
                'reply': legacy.get('reply_count', 0), 'view': int(tweet.get('views', {}).get('count', 0)),
                'bookmarks': legacy.get('bookmark_count', 0), 'screen_name': profile.get('screen_name')},
            archive_metadata={'source': 'x_web', 'tweet_id': tweet_id, 'possibly_sensitive': legacy.get('possibly_sensitive', False),
                'archive': {'type': 'twitter_status', 'version': '1', 'images': images, 'videos': videos}})
    except (KeyError, TypeError, ValueError, AttributeError):
        raise _error('parse_failed', 'X 推文正文或媒体结构不符合已核对契约') from None
