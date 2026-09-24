"""旧归档索引迁移必须保留媒体身份、来源角色与存储字段。"""
import json

from alembic import command
from sqlalchemy import create_engine, text

from app.core.database import migration_config


def test_archive_index_migration_preserves_items_and_is_applied_once():
    url = "https://fixture.invalid/shared.png"
    original = {
        "unrelated": {"keep": True},
        "archive": {
            "images": [{"url": url}, {"url": url, "type": "avatar", "is_avatar": True}],
            "stored_images": [
                {"orig_url": url, "key": "main.webp", "sha256": "main-hash", "size": 123,
                 "thumb_key": "thumb.webp", "thumb_sha256": "thumb-hash"},
                {"orig_url": url, "key": "main.webp", "type": "avatar", "is_avatar": True},
                {"orig_url": "https://fixture.invalid/legacy.png", "key": "legacy.webp", "type": "cover"},
                {"orig_url": "https://fixture.invalid/alias.png", "key": "main.webp"},
            ],
            "stored_videos": [{"orig_url": "https://fixture.invalid/video", "key": "video.mp4", "size": 456}],
            "markdown": "![image](local://main.webp)",
        },
        "processed_archive": {"stored_images": [{"key": "local-only.webp", "width": 200}]},
    }
    engine = create_engine("sqlite://")
    try:
        with engine.begin() as connection:
            connection.execute(text("CREATE TABLE contents (id INTEGER PRIMARY KEY, archive_metadata JSON)"))
            connection.execute(text("INSERT INTO contents VALUES (1, :metadata)"),
                               {"metadata": json.dumps(original)})
            config = migration_config()
            config.attributes["connection"] = connection
            command.stamp(config, "base")
            command.upgrade(config, "20260920_media_archive_items")
            raw = connection.execute(text("SELECT archive_metadata FROM contents")).scalar_one()
            migrated = json.loads(raw)
            archive = migrated["archive"]
            assert "stored_images" not in archive and "stored_videos" not in archive
            body, avatar, cover, alias = archive["images"]
            assert "type" not in body and "is_avatar" not in body
            assert avatar["type"] == "avatar" and avatar["is_avatar"] is True
            assert cover["type"] == "cover" and cover["stored_key"] == "legacy.webp"
            assert alias["url"] == "https://fixture.invalid/alias.png" and alias["stored_key"] == "main.webp"
            for item in (body, avatar):
                assert item["stored_key"] == "main.webp"
                assert item["stored_sha256"] == "main-hash"
                assert item["thumb_sha256"] == "thumb-hash"
            assert archive["videos"][0]["stored_key"] == "video.mp4"
            assert migrated["processed_archive"]["images"][0]["stored_key"] == "local-only.webp"
            assert archive["markdown"] == original["archive"]["markdown"]
            assert migrated["unrelated"] == original["unrelated"]
            command.upgrade(config, "20260920_media_archive_items")
            assert connection.execute(text("SELECT archive_metadata FROM contents")).scalar_one() == raw
    finally:
        engine.dispose()
