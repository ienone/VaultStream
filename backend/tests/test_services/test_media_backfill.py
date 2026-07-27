from types import SimpleNamespace

from app.models import LayoutType
from app.models.media import MediaRole, MediaType, MediaVariantKind
from app.services.media_backfill import (
    build_media_candidates,
    is_client_direct_allowed,
)


def _content(**overrides):
    values = {
        "cover_url": None,
        "author_avatar_url": None,
        "media_urls": [],
        "archive_metadata": None,
        "layout_type": LayoutType.ARTICLE,
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def test_processed_archive_links_original_to_local_variants_without_filename_guessing():
    content = _content(
        cover_url="local://blobs/cover.webp",
        author_avatar_url="local://blobs/avatar.webp",
        archive_metadata={
            "processed_archive": {
                "images": [
                    {
                        "url": "https://cdn.test/cover.jpg",
                        "stored_key": "blobs/cover.webp",
                        "thumb_key": "blobs/cover.thumb.webp",
                        "stored_width": 1200,
                        "stored_height": 800,
                    },
                    {
                        "url": "https://cdn.test/avatar.jpg",
                        "stored_key": "blobs/avatar.webp",
                        "type": "avatar",
                    },
                ],
            },
        },
    )

    candidates = build_media_candidates(content)

    cover = next(item for item in candidates if item.role == MediaRole.COVER)
    avatar = next(item for item in candidates if item.role == MediaRole.AVATAR)
    assert cover.original_url == "https://cdn.test/cover.jpg"
    assert [variant.kind for variant in cover.variants] == [
        MediaVariantKind.THUMBNAIL,
        MediaVariantKind.OPTIMIZED,
    ]
    assert avatar.original_url == "https://cdn.test/avatar.jpg"


def test_gallery_without_explicit_cover_promotes_first_image_only():
    content = _content(
        layout_type=LayoutType.GALLERY,
        archive_metadata={
            "archive": {
                "images": [
                    {"url": "https://cdn.test/one.jpg"},
                    {"url": "https://cdn.test/two.jpg"},
                ],
            },
        },
    )

    candidates = build_media_candidates(content)

    assert candidates[0].role == MediaRole.COVER
    assert candidates[0].position == 0
    assert candidates[1].role == MediaRole.GALLERY


def test_video_and_audio_are_part_of_same_asset_contract():
    content = _content(
        archive_metadata={
            "archive": {
                "videos": [
                    {
                        "url": "https://cdn.test/movie.mp4",
                        "stored_key": "blobs/movie.mp4",
                    },
                ],
            },
        },
        media_urls=["https://cdn.test/audio.mp3"],
    )

    candidates = build_media_candidates(content)

    assert any(item.media_type == MediaType.VIDEO for item in candidates)
    assert any(item.media_type == MediaType.AUDIO for item in candidates)


def test_client_direct_policy_rejects_credentials_and_private_literal_hosts():
    assert is_client_direct_allowed("https://cdn.example.test/image.jpg")
    assert not is_client_direct_allowed("https://user:secret@cdn.test/image.jpg")
    assert not is_client_direct_allowed("http://127.0.0.1/image.jpg")
    assert not is_client_direct_allowed("http://192.168.1.10/image.jpg")
    assert not is_client_direct_allowed("http://media.local/image.jpg")
