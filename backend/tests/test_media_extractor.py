from app.media.extractor import extract_media_urls, pick_preview_thumbnail


def test_pick_preview_thumbnail_prefers_archive_media_url():
    metadata = {
        "archive": {
            "images": [
                {"url": "https://cdn.example.com/1.jpg"},
                {"url": "https://cdn.example.com/2.jpg"},
            ]
        }
    }

    result = pick_preview_thumbnail(metadata, cover_url="https://fallback.example.com/cover.jpg")
    assert result == "https://cdn.example.com/1.jpg"


def test_pick_preview_thumbnail_falls_back_to_cover_url_when_no_media():
    metadata = {"archive": {"images": []}}

    result = pick_preview_thumbnail(metadata, cover_url="https://fallback.example.com/cover.jpg")
    assert result == "https://fallback.example.com/cover.jpg"


def test_extract_media_urls_rejects_avatar_items_for_preview_pipeline():
    metadata = {
        "archive": {
            "images": [
                {"url": "https://cdn.example.com/avatar.jpg", "type": "avatar"},
                {"url": "https://cdn.example.com/content.jpg"},
            ]
        }
    }

    items = extract_media_urls(metadata)
    assert items == [{"type": "photo", "url": "https://cdn.example.com/content.jpg"}]
