"""
Tests for RSS Discovery Scraper (Step 3)
"""
import pytest
import httpx
import respx

from app.adapters.discovery.rss import RSSDiscoveryScraper


SAMPLE_RSS_FEED = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
<channel>
    <title>Test Blog</title>
    <link>https://example.com</link>
    <item>
        <title>Article One</title>
        <link>https://example.com/article-1</link>
        <guid>entry-001</guid>
        <pubDate>Thu, 06 Mar 2026 10:00:00 +0000</pubDate>
        <description>First article content</description>
        <category>tech</category>
    </item>
    <item>
        <title>Article Two</title>
        <link>https://example.com/article-2</link>
        <guid>entry-002</guid>
        <pubDate>Wed, 05 Mar 2026 08:00:00 +0000</pubDate>
        <description>Second article content</description>
    </item>
</channel>
</rss>"""

SAMPLE_ATOM_FEED = """<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
    <title>Atom Blog</title>
    <entry>
        <title>Atom Post</title>
        <link href="https://atom.example.com/post-1"/>
        <id>atom-001</id>
        <updated>2026-03-06T12:00:00Z</updated>
        <summary>Atom summary text</summary>
        <category term="ai"/>
        <category term="ml"/>
    </entry>
</feed>"""

SAMPLE_RSS_FEED_WITH_MEDIA_COVER = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
<channel>
    <title>Media Feed</title>
    <item>
        <title>Covered Article</title>
        <link>https://example.com/covered-article</link>
        <guid>covered-001</guid>
        <media:thumbnail url="https://cdn.example.com/thumb.jpg" width="640" height="360" />
        <media:content url="https://cdn.example.com/media-content.jpg" medium="image" />
        <enclosure url="https://cdn.example.com/enclosure.jpg" type="image/jpeg" />
        <description><![CDATA[<p>Body text</p><img src="https://cdn.example.com/body.jpg" alt="body" />]]></description>
    </item>
</channel>
</rss>"""

SAMPLE_RSS_FEED_WITH_LAZY_BODY_IMAGE = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
<channel>
    <title>Lazy Feed</title>
    <item>
        <title>Lazy Article</title>
        <link>https://example.com/lazy-article</link>
        <guid>lazy-001</guid>
        <description><![CDATA[
            <p>Intro</p>
            <img src="//img.example.com/placeholder.png" data-original="https://cdn.example.com/real-image.jpg" alt="hero" />
        ]]></description>
    </item>
</channel>
</rss>"""


class TestRSSDiscoveryScraper:

    @respx.mock
    @pytest.mark.asyncio
    async def test_fetch_rss_items(self):
        """基本 RSS 抓取：正确解析条目字段"""
        respx.get("https://example.com/feed.xml").mock(
            return_value=httpx.Response(200, text=SAMPLE_RSS_FEED)
        )

        scraper = RSSDiscoveryScraper({"url": "https://example.com/feed.xml"})
        items, cursor = await scraper.fetch()

        assert len(items) == 2
        assert items[0].title == "Article One"
        assert items[0].url == "https://example.com/article-1"
        assert items[0].content == "First article content"
        assert items[0].published_at is not None
        assert cursor == "entry-001"

    @respx.mock
    @pytest.mark.asyncio
    async def test_fetch_atom_items(self):
        """Atom feed 解析"""
        respx.get("https://atom.example.com/feed").mock(
            return_value=httpx.Response(200, text=SAMPLE_ATOM_FEED)
        )

        scraper = RSSDiscoveryScraper({"url": "https://atom.example.com/feed"})
        items, cursor = await scraper.fetch()

        assert len(items) == 1
        assert items[0].title == "Atom Post"
        assert items[0].url == "https://atom.example.com/post-1"
        assert items[0].content == "Atom summary text"
        assert "ai" in items[0].source_tags
        assert "ml" in items[0].source_tags

    @respx.mock
    @pytest.mark.asyncio
    async def test_fetch_prefers_rss_cover_sources_before_body_images(self):
        """media:thumbnail 等显式 RSS 封面字段优先于正文首图。"""
        respx.get("https://example.com/media.xml").mock(
            return_value=httpx.Response(200, text=SAMPLE_RSS_FEED_WITH_MEDIA_COVER)
        )

        scraper = RSSDiscoveryScraper({"url": "https://example.com/media.xml"})
        items, _ = await scraper.fetch()

        assert len(items) == 1
        assert items[0].cover_url == "https://cdn.example.com/thumb.jpg"
        assert items[0].media_urls == ["https://cdn.example.com/body.jpg"]

    @respx.mock
    @pytest.mark.asyncio
    async def test_fetch_falls_back_to_first_real_body_image(self):
        """无显式 RSS 封面时，回退到正文首张真实图片而不是懒加载占位图。"""
        respx.get("https://example.com/lazy.xml").mock(
            return_value=httpx.Response(200, text=SAMPLE_RSS_FEED_WITH_LAZY_BODY_IMAGE)
        )

        scraper = RSSDiscoveryScraper({"url": "https://example.com/lazy.xml"})
        items, _ = await scraper.fetch()

        assert len(items) == 1
        assert items[0].cover_url == "https://cdn.example.com/real-image.jpg"
        assert items[0].media_urls == ["https://cdn.example.com/real-image.jpg"]
        assert "https://cdn.example.com/real-image.jpg" in items[0].content

    @respx.mock
    @pytest.mark.asyncio
    async def test_incremental_fetch_with_cursor(self):
        """增量抓取：遇到 last_cursor 匹配的 entry 时停止"""
        respx.get("https://example.com/feed.xml").mock(
            return_value=httpx.Response(200, text=SAMPLE_RSS_FEED)
        )

        scraper = RSSDiscoveryScraper({"url": "https://example.com/feed.xml"})
        items, cursor = await scraper.fetch(last_cursor="entry-002")

        assert len(items) == 1
        assert items[0].title == "Article One"

    @respx.mock
    @pytest.mark.asyncio
    async def test_category_injected_into_tags(self):
        """config 中的 category 应追加到 source_tags"""
        respx.get("https://example.com/feed.xml").mock(
            return_value=httpx.Response(200, text=SAMPLE_RSS_FEED)
        )

        scraper = RSSDiscoveryScraper({
            "url": "https://example.com/feed.xml",
            "category": "devops",
        })
        items, _ = await scraper.fetch()

        assert "devops" in items[0].source_tags

    @respx.mock
    @pytest.mark.asyncio
    async def test_http_error_returns_empty(self):
        """HTTP 错误时返回空列表而非抛异常"""
        respx.get("https://example.com/feed.xml").mock(
            return_value=httpx.Response(500, text="Server Error")
        )

        scraper = RSSDiscoveryScraper({"url": "https://example.com/feed.xml"})
        items, cursor = await scraper.fetch()

        assert items == []
        assert cursor is None

    @pytest.mark.asyncio
    async def test_missing_url_returns_empty(self):
        """config 缺少 url 时返回空"""
        scraper = RSSDiscoveryScraper({})
        items, cursor = await scraper.fetch()

        assert items == []

    @respx.mock
    @pytest.mark.asyncio
    async def test_raw_metadata_contains_entry_id(self):
        """raw_metadata 应包含 feed_url 和 entry_id"""
        respx.get("https://example.com/feed.xml").mock(
            return_value=httpx.Response(200, text=SAMPLE_RSS_FEED)
        )

        scraper = RSSDiscoveryScraper({"url": "https://example.com/feed.xml"})
        items, _ = await scraper.fetch()

        assert items[0].raw_metadata["entry_id"] == "entry-001"
        assert items[0].raw_metadata["feed_url"] == "https://example.com/feed.xml"
