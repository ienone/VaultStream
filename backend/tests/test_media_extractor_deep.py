import pytest
from app.media.extractor import extract_media_urls, _is_avatar_like

def test_is_avatar_like():
    """Test avatar detection logic."""
    assert _is_avatar_like({"type": "avatar", "url": "any"}) is True
    assert _is_avatar_like({"type": "author_avatar", "url": "any"}) is True
    assert _is_avatar_like({"is_avatar": True, "url": "any"}) is True
    assert _is_avatar_like({"url": "https://cdn.com/avatar_123.jpg"}) is True
    assert _is_avatar_like({"url": "https://cdn.com/profile_image.png"}) is True
    assert _is_avatar_like({"url": "https://cdn.com/normal.jpg"}) is False

def test_extract_media_urls_priority():
    """Test URL extraction priority (Original vs Stored)."""
    metadata = {
        "archive": {
            "images": [
                {"url": "orig1", "stored_url": "stored1"},
                {"url": "orig2"}
            ]
        }
    }
    
    # Default: Prefer original
    results = extract_media_urls(metadata)
    assert len(results) == 2
    assert results[0]["url"] == "orig1"
    assert results[1]["url"] == "orig2"
    
    # Prefer stored
    results = extract_media_urls(metadata, prefer_stored=True)
    assert results[0]["url"] == "stored1"
    assert results[1]["url"] == "orig2" # Fallback to original

def test_extract_media_urls_with_avatar_filtering():
    """Test that avatars are filtered out from media list."""
    metadata = {
        "archive": {
            "images": [
                {"url": "normal_pic", "type": "photo"},
                {"url": "my_avatar", "type": "avatar"}
            ]
        }
    }
    results = extract_media_urls(metadata)
    assert len(results) == 1
    assert results[0]["url"] == "normal_pic"

def test_extract_media_urls_fallback_to_cover():
    """Test fallback to cover_url when no images found."""
    metadata = {"archive": {"images": []}}
    results = extract_media_urls(metadata, cover_url="cover_me")
    assert len(results) == 1
    assert results[0]["type"] == "photo"
    assert results[0]["url"] == "cover_me"

    # No fallback when cover_url is empty/None
    assert extract_media_urls(metadata, cover_url=None) == []
    assert extract_media_urls(metadata, cover_url="  ") == []

    # No fallback when images exist
    metadata_with_images = {"archive": {"images": [{"url": "real.jpg"}]}}
    results = extract_media_urls(metadata_with_images, cover_url="cover_me")
    assert len(results) == 1
    assert results[0]["url"] == "real.jpg"

def test_extract_media_urls_complex_nesting():
    """Test deeply nested or malformed metadata."""
    assert extract_media_urls(None) == []
    assert extract_media_urls({}) == []
    assert extract_media_urls({"archive": "not_a_dict"}) == []
