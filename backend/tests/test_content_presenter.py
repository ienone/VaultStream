"""
Tests for app.services.content_presenter — pure-function unit tests.
"""
import pytest
from types import SimpleNamespace

from app.models import LayoutType
from app.services.content_presenter import (
    compute_effective_layout_type,
    compute_display_title,
    compute_author_avatar_url,
    transform_media_url,
    transform_content_detail,
)

BASE_URL = "https://example.com"


# ── compute_effective_layout_type ──────────────────────────────────


def test_compute_effective_layout_type_override_wins():
    content = SimpleNamespace(
        layout_type_override=LayoutType.VIDEO,
        layout_type=LayoutType.ARTICLE,
    )
    assert compute_effective_layout_type(content) == "video"


def test_compute_effective_layout_type_fallback_to_system():
    content = SimpleNamespace(layout_type_override=None, layout_type=LayoutType.GALLERY)
    assert compute_effective_layout_type(content) == "gallery"


def test_compute_effective_layout_type_none():
    content = SimpleNamespace(layout_type_override=None, layout_type=None)
    assert compute_effective_layout_type(content) is None


# ── compute_display_title ──────────────────────────────────────────


def test_compute_display_title_uses_title():
    content = SimpleNamespace(title="好文章", body="正文内容")
    assert compute_display_title(content) == "好文章"


def test_compute_display_title_falls_back_to_body():
    content = SimpleNamespace(title=None, body="今天天气不错，适合出去走走")
    result = compute_display_title(content)
    assert result != "无标题"
    assert "今天" in result


# ── compute_author_avatar_url ──────────────────────────────────────


def test_compute_author_avatar_url():
    content = SimpleNamespace(author_avatar_url="https://cdn.example.com/avatar.jpg")
    assert compute_author_avatar_url(content) == "https://cdn.example.com/avatar.jpg"


def test_compute_author_avatar_url_none():
    content = SimpleNamespace(author_avatar_url=None)
    assert compute_author_avatar_url(content) is None


# ── transform_media_url ───────────────────────────────────────────


def test_transform_media_url_local_protocol():
    result = transform_media_url("local://abc/def.jpg", BASE_URL)
    assert result == f"{BASE_URL}/api/v1/media/abc/def.jpg"


def test_transform_media_url_http_unchanged():
    url = "https://cdn.example.com/image.png"
    assert transform_media_url(url, BASE_URL) == url


def test_transform_media_url_none():
    assert transform_media_url(None, BASE_URL) is None


# ── transform_content_detail ──────────────────────────────────────


def _make_detail(**overrides):
    defaults = dict(
        cover_url=None,
        author_avatar_url=None,
        media_urls=None,
        rich_payload=None,
        context_data=None,
        body=None,
        title=None,
    )
    defaults.update(overrides)
    return SimpleNamespace(**defaults)


def test_transform_content_detail_full():
    detail = _make_detail(
        cover_url="local://cover.jpg",
        author_avatar_url="local://avatar.png",
        media_urls=["local://m1.jpg", "https://ext.com/m2.jpg"],
    )
    result = transform_content_detail(detail, BASE_URL)
    assert result.cover_url == f"{BASE_URL}/api/v1/media/cover.jpg"
    assert result.author_avatar_url == f"{BASE_URL}/api/v1/media/avatar.png"
    assert result.media_urls == [
        f"{BASE_URL}/api/v1/media/m1.jpg",
        "https://ext.com/m2.jpg",
    ]


def test_transform_content_detail_rich_payload():
    detail = _make_detail(
        rich_payload={
            "blocks": [
                {
                    "type": "card",
                    "data": {
                        "cover_url": "local://block_cover.jpg",
                        "author_avatar_url": "local://block_avatar.png",
                    },
                }
            ]
        }
    )
    transform_content_detail(detail, BASE_URL)
    block_data = detail.rich_payload["blocks"][0]["data"]
    assert block_data["cover_url"] == f"{BASE_URL}/api/v1/media/block_cover.jpg"
    assert block_data["author_avatar_url"] == f"{BASE_URL}/api/v1/media/block_avatar.png"


def test_transform_content_detail_context_data():
    detail = _make_detail(
        context_data={
            "cover_url": "local://ctx_cover.jpg",
            "author_avatar_url": "local://ctx_avatar.png",
        }
    )
    transform_content_detail(detail, BASE_URL)
    assert detail.context_data["cover_url"] == f"{BASE_URL}/api/v1/media/ctx_cover.jpg"
    assert detail.context_data["author_avatar_url"] == f"{BASE_URL}/api/v1/media/ctx_avatar.png"


def test_transform_content_detail_body_local_urls():
    detail = _make_detail(
        body='看这张图 local://photo/abc.jpg 还有 local://video/xyz.mp4 好看',
    )
    transform_content_detail(detail, BASE_URL)
    assert "local://" not in detail.body
    assert f"{BASE_URL}/api/v1/media/photo/abc.jpg" in detail.body
    assert f"{BASE_URL}/api/v1/media/video/xyz.mp4" in detail.body


def test_transform_content_detail_ufffd_cleanup():
    detail = _make_detail(
        body="hello\ufffdworld",
        title="好\ufffd标题",
    )
    transform_content_detail(detail, BASE_URL)
    assert "\ufffd" not in detail.body
    assert detail.body == "helloworld"
    assert "\ufffd" not in detail.title
    assert detail.title == "好标题"
