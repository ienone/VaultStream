import httpx
import pytest
from unittest.mock import AsyncMock

from app.adapters.rss import RssAdapter
from app.models.base import Platform


def _mock_response(url: str, content: str) -> httpx.Response:
    return httpx.Response(
        200,
        content=content.encode("utf-8"),
        request=httpx.Request("GET", url),
    )


SAMPLE_RSS_FEED = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
<channel>
  <title>RSS Channel</title>
  <link>https://example.com</link>
  <item>
    <title>Entry One</title>
    <link>https://example.com/article-1</link>
    <guid>entry-001</guid>
    <pubDate>Thu, 06 Mar 2026 10:00:00 +0000</pubDate>
    <category>tech</category>
    <media:thumbnail url="https://cdn.example.com/thumb.jpg" />
    <media:content url="https://cdn.example.com/video.mp4" medium="video" />
    <description><![CDATA[
      <p>Intro</p>
      <img src="//cdn.example.com/placeholder.jpg" data-original="https://cdn.example.com/body.jpg" alt="body" />
      <a href="/jump">jump</a>
    ]]></description>
  </item>
</channel>
</rss>"""


SAMPLE_ATOM_FEED = """<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Channel</title>
  <entry>
    <title>Atom Entry</title>
    <id>tag:example.com,2026:atom-1</id>
    <link href="https://atom.example.com/posts/1" rel="alternate" />
    <updated>2026-03-06T12:00:00Z</updated>
    <category term="ai" />
    <category term="ml" />
    <content type="html"><![CDATA[
      <div><strong>Hello</strong><img src="/img/a.png" alt="a" /></div>
    ]]></content>
    <summary>Summary should be lower priority</summary>
  </entry>
</feed>"""


SAMPLE_RSS_TWO_ITEMS = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
<channel>
  <title>Two Entries</title>
  <item>
    <title>Newest</title>
    <link>https://example.com/newest</link>
    <guid>newest-001</guid>
    <description>newest body</description>
  </item>
  <item>
    <title>Older</title>
    <link>https://example.com/older</link>
    <guid>older-001</guid>
    <description>older body</description>
  </item>
</channel>
</rss>"""


@pytest.mark.asyncio
async def test_parse_channel_normalizes_rss_with_archive_and_media():
    adapter = RssAdapter()
    try:
        adapter.client.get = AsyncMock(
            return_value=_mock_response("https://example.com/feed.xml", SAMPLE_RSS_FEED)
        )

        items = await adapter.parse_channel("https://example.com/feed.xml")
        assert len(items) == 1

        item = items[0]
        assert item.platform == Platform.RSS.value
        assert item.content_id == "entry-001"
        assert item.clean_url == "https://example.com/article-1"
        assert item.cover_url == "https://cdn.example.com/thumb.jpg"
        assert item.media_urls == [
            "https://cdn.example.com/body.jpg",
            "https://cdn.example.com/video.mp4",
        ]
        assert item.published_at is not None
        assert "tech" in item.source_tags
        assert "![body](https://cdn.example.com/body.jpg)" in (item.body or "")
        assert "[jump](https://example.com/jump)" in (item.body or "")

        archive = (item.archive_metadata or {}).get("archive", {})
        assert archive.get("type") == "rss_article"
        assert any(img.get("url") == "https://cdn.example.com/thumb.jpg" and img.get("type") == "cover" for img in archive.get("images", []))
        assert any(v.get("url") == "https://cdn.example.com/video.mp4" for v in archive.get("videos", []))
    finally:
        await adapter.close()


@pytest.mark.asyncio
async def test_parse_channel_normalizes_atom_priority_and_relative_urls():
    adapter = RssAdapter()
    try:
        adapter.client.get = AsyncMock(
            return_value=_mock_response("https://atom.example.com/feed", SAMPLE_ATOM_FEED)
        )

        items = await adapter.parse_channel("https://atom.example.com/feed")
        assert len(items) == 1

        item = items[0]
        assert item.content_id == "tag:example.com,2026:atom-1"
        assert item.clean_url == "https://atom.example.com/posts/1"
        assert item.published_at is not None
        assert "ai" in item.source_tags
        assert "ml" in item.source_tags

        # content 优先于 summary，且相对路径被绝对化
        assert "Summary should be lower priority" not in (item.body or "")
        assert "![a](https://atom.example.com/img/a.png)" in (item.body or "")
        assert item.media_urls == ["https://atom.example.com/img/a.png"]

        archive = (item.archive_metadata or {}).get("archive", {})
        assert any(img.get("url") == "https://atom.example.com/img/a.png" for img in archive.get("images", []))
    finally:
        await adapter.close()


@pytest.mark.asyncio
async def test_parse_returns_latest_entry():
    adapter = RssAdapter()
    try:
        adapter.client.get = AsyncMock(
            return_value=_mock_response("https://example.com/feed.xml", SAMPLE_RSS_TWO_ITEMS)
        )

        parsed = await adapter.parse("https://example.com/feed.xml")
        assert parsed.title == "Newest"
        assert parsed.clean_url == "https://example.com/newest"
        assert parsed.content_id == "newest-001"
    finally:
        await adapter.close()
