import pytest
from datetime import datetime

from app.utils.text_formatters import (
    format_number,
    strip_markdown,
    _normalize_render_config,
    _apply_template,
    format_content_with_render_config,
    format_content_for_tg,
    _format_twitter_message,
    _format_bilibili_message,
    _format_default_message,
)


# ---------------------------------------------------------------------------
# format_number
# ---------------------------------------------------------------------------

def test_format_number_zero():
    assert format_number(0) == "0"


def test_format_number_none():
    assert format_number(None) == "0"


def test_format_number_below_10000():
    assert format_number(9999) == "9999"


def test_format_number_exactly_10000():
    assert format_number(10000) == "1.00万"


def test_format_number_above_10000():
    assert format_number(15000) == "1.50万"


def test_format_number_string_input():
    assert format_number("5000") == "5000"


def test_format_number_invalid_input():
    assert format_number("abc") == "abc"


def test_format_number_empty_string():
    # empty string is falsy → returns "0"
    assert format_number("") == "0"


# ---------------------------------------------------------------------------
# strip_markdown
# ---------------------------------------------------------------------------

def test_strip_markdown_none():
    assert strip_markdown(None) is None


def test_strip_markdown_empty():
    assert strip_markdown("") == ""


def test_strip_markdown_headings():
    assert strip_markdown("# Heading 1") == "Heading 1"
    assert strip_markdown("## Heading 2") == "Heading 2"
    assert strip_markdown("###### Heading 6") == "Heading 6"


def test_strip_markdown_bold():
    assert strip_markdown("**bold**") == "bold"
    assert strip_markdown("__bold__") == "bold"


def test_strip_markdown_italic():
    assert strip_markdown("*italic*") == "italic"
    assert strip_markdown("_italic_") == "italic"


def test_strip_markdown_strikethrough():
    assert strip_markdown("~~deleted~~") == "deleted"


def test_strip_markdown_links():
    assert strip_markdown("[click here](https://example.com)") == "click here"


def test_strip_markdown_images():
    assert strip_markdown("![alt text](https://img.png)") == "alt text"
    assert strip_markdown("![](https://img.png)") == ""


def test_strip_markdown_inline_code():
    assert strip_markdown("`some code`") == "some code"


def test_strip_markdown_blockquote():
    assert strip_markdown("> quoted text") == "quoted text"


def test_strip_markdown_horizontal_rule():
    assert strip_markdown("---") == ""


def test_strip_markdown_multiple_blank_lines():
    result = strip_markdown("a\n\n\n\nb")
    assert result == "a\n\nb"


def test_strip_markdown_combined():
    md = "# Title\n\n**bold** and *italic*\n\n> quote\n\n[link](url)"
    result = strip_markdown(md)
    assert "# " not in result
    assert "**" not in result
    assert "*" not in result
    assert ">" not in result
    assert "[link](url)" not in result
    assert "link" in result


# ---------------------------------------------------------------------------
# _normalize_render_config
# ---------------------------------------------------------------------------

def test_normalize_render_config_none():
    assert _normalize_render_config(None) == {}


def test_normalize_render_config_empty_dict():
    assert _normalize_render_config({}) == {}


def test_normalize_render_config_flat():
    cfg = {"show_title": False, "author_mode": "name"}
    result = _normalize_render_config(cfg)
    assert result == {"show_title": False, "author_mode": "name"}


def test_normalize_render_config_with_structure_key():
    cfg = {"structure": {"show_title": True, "link_mode": "none"}, "extra": "ignored"}
    result = _normalize_render_config(cfg)
    assert result == {"show_title": True, "link_mode": "none"}


# ---------------------------------------------------------------------------
# _apply_template
# ---------------------------------------------------------------------------

def test_apply_template_empty():
    assert _apply_template("", {}) == ""


def test_apply_template_none():
    assert _apply_template(None, {}) == ""


def test_apply_template_date_placeholder():
    result = _apply_template("Today is {{date}}", {})
    today = datetime.utcnow().strftime("%Y-%m-%d")
    assert result == f"Today is {today}"


def test_apply_template_title_placeholder():
    result = _apply_template("Title: {{title}}", {"title": "Hello"})
    assert result == "Title: Hello"


def test_apply_template_title_falls_back_to_body():
    result = _apply_template("{{title}}", {"body": "FallbackBody"})
    assert result == "FallbackBody"


def test_apply_template_no_placeholders():
    assert _apply_template("plain text", {}) == "plain text"


# ---------------------------------------------------------------------------
# format_content_with_render_config
# ---------------------------------------------------------------------------

_SAMPLE_CONTENT = {
    "title": "Test Title",
    "body": "Full body text here",
    "summary": "Short summary",
    "author_name": "Alice",
    "author_id": "alice_123",
    "url": "https://example.com/original?tracking=1",
    "clean_url": "https://example.com/clean",
    "canonical_url": "https://example.com/canonical",
    "tags": ["python", "testing"],
}


def test_render_config_rich_text_title_is_bold():
    result = format_content_with_render_config(
        _SAMPLE_CONTENT, {}, rich_text=True, platform="bilibili"
    )
    assert "<b>Test Title</b>" in result


def test_render_config_plain_text_no_html():
    result = format_content_with_render_config(
        _SAMPLE_CONTENT, {}, rich_text=False, platform="bilibili"
    )
    assert "<b>" not in result
    assert "Test Title" in result


def test_render_config_show_platform_id():
    result = format_content_with_render_config(
        _SAMPLE_CONTENT, {"show_platform_id": True}, rich_text=False, platform="bilibili"
    )
    assert "Bilibili" in result


def test_render_config_hide_platform_id():
    result = format_content_with_render_config(
        _SAMPLE_CONTENT, {"show_platform_id": False}, rich_text=False, platform="bilibili"
    )
    assert "Bilibili" not in result


def test_render_config_unknown_platform_label():
    result = format_content_with_render_config(
        _SAMPLE_CONTENT, {"show_platform_id": True}, rich_text=False, platform="mastodon"
    )
    assert "mastodon" in result


def test_render_config_show_title_false():
    result = format_content_with_render_config(
        _SAMPLE_CONTENT, {"show_title": False}, rich_text=False, platform="twitter"
    )
    assert "Test Title" not in result


def test_render_config_author_mode_full():
    result = format_content_with_render_config(
        _SAMPLE_CONTENT, {"author_mode": "full"}, rich_text=False, platform="twitter"
    )
    assert "Alice" in result
    assert "alice_123" in result


def test_render_config_author_mode_name():
    result = format_content_with_render_config(
        _SAMPLE_CONTENT, {"author_mode": "name"}, rich_text=False, platform="twitter"
    )
    assert "Alice" in result
    assert "alice_123" not in result


def test_render_config_author_mode_none():
    result = format_content_with_render_config(
        _SAMPLE_CONTENT, {"author_mode": "none"}, rich_text=False, platform="twitter"
    )
    assert "Alice" not in result


def test_render_config_content_mode_summary():
    result = format_content_with_render_config(
        _SAMPLE_CONTENT, {"content_mode": "summary"}, rich_text=False, platform="twitter"
    )
    assert "Short summary" in result


def test_render_config_content_mode_summary_truncates():
    long_content = {**_SAMPLE_CONTENT, "summary": "Q" * 300}
    result = format_content_with_render_config(
        long_content, {"content_mode": "summary"}, rich_text=False, platform="twitter"
    )
    assert result.count("Q") == 200
    assert "..." in result


def test_render_config_content_mode_full():
    long_content = {**_SAMPLE_CONTENT, "summary": "Q" * 300}
    result = format_content_with_render_config(
        long_content, {"content_mode": "full"}, rich_text=False, platform="twitter"
    )
    assert result.count("Q") == 300


def test_render_config_content_mode_hidden():
    result = format_content_with_render_config(
        _SAMPLE_CONTENT, {"content_mode": "hidden"}, rich_text=False, platform="twitter"
    )
    assert "Short summary" not in result
    assert "Full body" not in result


def test_render_config_link_mode_clean():
    result = format_content_with_render_config(
        _SAMPLE_CONTENT, {"link_mode": "clean"}, rich_text=False, platform="twitter"
    )
    assert "https://example.com/clean" in result


def test_render_config_link_mode_original():
    result = format_content_with_render_config(
        _SAMPLE_CONTENT, {"link_mode": "original"}, rich_text=False, platform="twitter"
    )
    assert "https://example.com/original?tracking=1" in result


def test_render_config_link_mode_none():
    result = format_content_with_render_config(
        _SAMPLE_CONTENT, {"link_mode": "none"}, rich_text=False, platform="twitter"
    )
    assert "链接" not in result


def test_render_config_show_tags():
    result = format_content_with_render_config(
        _SAMPLE_CONTENT, {"show_tags": True}, rich_text=False, platform="twitter"
    )
    assert "#python" in result
    assert "#testing" in result


def test_render_config_hide_tags_by_default():
    result = format_content_with_render_config(
        _SAMPLE_CONTENT, {}, rich_text=False, platform="twitter"
    )
    assert "#python" not in result


def test_render_config_header_footer():
    result = format_content_with_render_config(
        _SAMPLE_CONTENT,
        {"header_text": "=== HEAD ===", "footer_text": "=== FOOT ==="},
        rich_text=False,
        platform="twitter",
    )
    lines = result.split("\n")
    assert lines[0] == "=== HEAD ==="
    assert lines[-1] == "=== FOOT ==="


def test_render_config_header_with_template():
    result = format_content_with_render_config(
        _SAMPLE_CONTENT,
        {"header_text": "Post: {{title}}"},
        rich_text=False,
        platform="twitter",
    )
    assert "Post: Test Title" in result


def test_render_config_rich_text_escapes_html():
    content = {**_SAMPLE_CONTENT, "title": "<script>alert(1)</script>"}
    result = format_content_with_render_config(
        content, {}, rich_text=True, platform="twitter"
    )
    assert "<script>" not in result
    assert "&lt;script&gt;" in result


# ---------------------------------------------------------------------------
# format_content_for_tg – dispatch
# ---------------------------------------------------------------------------

def test_format_content_for_tg_bilibili_dispatch():
    content = {"platform": "bilibili", "title": "B站视频", "author_name": "UP主"}
    result = format_content_for_tg(content)
    assert "[视频]" in result
    assert "UP：UP主" in result


def test_format_content_for_tg_twitter_dispatch():
    content = {"platform": "twitter", "author_name": "Tweeter"}
    result = format_content_for_tg(content)
    assert "Tweeter" in result


def test_format_content_for_tg_default_dispatch():
    content = {"platform": "weibo", "title": "微博标题"}
    result = format_content_for_tg(content)
    assert "微博标题" in result


# ---------------------------------------------------------------------------
# _format_bilibili_message
# ---------------------------------------------------------------------------

def _bili_base(**overrides):
    base = {
        "title": "测试视频",
        "author_name": "TestUP",
        "published_at": "2025-01-15T12:00:00",
        "clean_url": "https://b23.tv/xxx",
        "view_count": 12345,
        "like_count": 100,
        "collect_count": 50,
        "share_count": 20,
        "comment_count": 30,
        "extra_stats": {"coin": 10, "danmaku": 5},
    }
    base.update(overrides)
    return base


def test_bili_video_type():
    result = _format_bilibili_message(_bili_base(content_type="video"))
    assert "[视频]" in result
    assert "播放：" in result
    assert "弹幕：" in result
    assert "硬币：" in result


def test_bili_live_streaming():
    result = _format_bilibili_message(
        _bili_base(content_type="live", extra_stats={"live_status": 1})
    )
    assert "直播中" in result
    assert "人气：" in result


def test_bili_live_not_streaming():
    result = _format_bilibili_message(
        _bili_base(content_type="live", extra_stats={"live_status": 0})
    )
    assert "未开播" in result


def test_bili_live_looping():
    result = _format_bilibili_message(
        _bili_base(content_type="live", extra_stats={"live_status": 2})
    )
    assert "轮播中" in result


def test_bili_article_type():
    result = _format_bilibili_message(_bili_base(content_type="article"))
    assert "[专栏]" in result
    assert "阅读：" in result


def test_bili_dynamic_type():
    result = _format_bilibili_message(_bili_base(content_type="dynamic"))
    assert "[动态]" in result
    assert "转发：" in result


def test_bili_bangumi_type():
    result = _format_bilibili_message(_bili_base(content_type="bangumi"))
    assert "[番剧/电影]" in result


def test_bili_description_truncation():
    long_desc = "字" * 400
    result = _format_bilibili_message(_bili_base(summary=long_desc))
    assert "..." in result
    # 300 chars + "..." should appear; the full 400 should not
    assert "字" * 301 not in result


def test_bili_tags():
    result = _format_bilibili_message(_bili_base(tags=["游戏", "科技"]))
    assert "#游戏" in result
    assert "#科技" in result


def test_bili_no_tags():
    result = _format_bilibili_message(_bili_base())
    assert "#" not in result


def test_bili_published_at_formatting():
    result = _format_bilibili_message(_bili_base())
    assert "2025-01-15 12:00:00" in result
    assert "T" not in result.split("日期：")[1].split("\n")[0]


def test_bili_html_escapes_title():
    result = _format_bilibili_message(_bili_base(title="<b>evil</b>"))
    assert "&lt;b&gt;evil&lt;/b&gt;" in result


# ---------------------------------------------------------------------------
# _format_twitter_message
# ---------------------------------------------------------------------------

def _tweet_base(**overrides):
    base = {
        "author_name": "TestUser",
        "clean_url": "https://x.com/test/status/123",
        "view_count": 5000,
        "like_count": 200,
        "share_count": 50,
        "comment_count": 10,
        "extra_stats": {"screen_name": "testuser", "bookmarks": 30},
    }
    base.update(overrides)
    return base


def test_twitter_author_with_handle():
    result = _format_twitter_message(_tweet_base())
    assert "TestUser (@testuser)" in result


def test_twitter_author_without_handle():
    result = _format_twitter_message(
        _tweet_base(extra_stats={})
    )
    assert "TestUser" in result
    assert "@" not in result


def test_twitter_reply_info():
    result = _format_twitter_message(
        _tweet_base(extra_stats={"screen_name": "u", "replying_to": "original_user"})
    )
    assert "回复：@original_user" in result


def test_twitter_stats():
    result = _format_twitter_message(_tweet_base())
    assert "浏览 5000" in result
    assert "点赞 200" in result
    assert "转发 50" in result
    assert "回复 10" in result
    assert "收藏 30" in result


def test_twitter_body_truncation():
    long_body = "w" * 600
    result = _format_twitter_message(_tweet_base(body=long_body))
    assert "..." in result
    assert "w" * 501 not in result


def test_twitter_tags():
    result = _format_twitter_message(_tweet_base(tags=["news", "tech"]))
    assert "#news" in result
    assert "#tech" in result


def test_twitter_published_at():
    result = _format_twitter_message(
        _tweet_base(published_at="2025-06-01T18:30:00")
    )
    assert "2025-06-01 18:30:00" in result


def test_twitter_link():
    result = _format_twitter_message(_tweet_base())
    assert "https://x.com/test/status/123" in result


def test_twitter_no_author_name():
    result = _format_twitter_message(_tweet_base(author_name=None))
    assert "未知" in result


# ---------------------------------------------------------------------------
# _format_default_message
# ---------------------------------------------------------------------------

def test_default_with_all_fields():
    content = {
        "title": "Default Title",
        "author_name": "Bob",
        "body": "Some body text",
        "clean_url": "https://example.com",
        "view_count": 100,
        "like_count": 20,
        "collect_count": 5,
        "tags": ["misc"],
    }
    result = _format_default_message(content)
    assert "<b>Default Title</b>" in result
    assert "作者：Bob" in result
    assert "浏览 100" in result
    assert "点赞 20" in result
    assert "收藏 5" in result
    assert "Some body text" in result
    assert "#misc" in result
    assert "https://example.com" in result


def test_default_minimal():
    result = _format_default_message({"clean_url": "https://example.com"})
    assert "链接：https://example.com" in result
    # No title/author/body/tags sections
    assert "<b>" not in result
    assert "作者" not in result
    assert "#" not in result


def test_default_body_truncation():
    content = {"body": "z" * 300, "clean_url": "https://example.com"}
    result = _format_default_message(content)
    assert "..." in result
    assert "z" * 201 not in result


def test_default_html_escapes():
    content = {"title": "<h1>XSS</h1>", "clean_url": ""}
    result = _format_default_message(content)
    assert "&lt;h1&gt;XSS&lt;/h1&gt;" in result
