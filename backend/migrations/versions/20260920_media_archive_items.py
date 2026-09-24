"""Merge duplicate stored-media indexes into their archive items."""
import json

from alembic import op
from sqlalchemy import text

revision = "20260920_media_archive_items"
down_revision = None
branch_labels = None
depends_on = None


def _merge_archive(archive):
    changed = False
    for collection in ("images", "videos"):
        if f"stored_{collection}" not in archive:
            continue
        legacy = archive.pop(f"stored_{collection}") or []
        changed = True
        items = archive.setdefault(collection, [])
        for stored in legacy:
            original, key = stored.get("orig_url"), stored.get("key") or stored.get("stored_key")
            targets = [item for item in items if
                       (original and item.get("url") == original and item.get("stored_key") in (None, key))
                       or (key and item.get("stored_key") == key
                           and (not original or item.get("url") in (None, original)))]
            is_new = not targets
            if is_new:
                target = {"url": original} if original else {}
                items.append(target)
                targets = [target]
            fields = {name: f"stored_{name}" for name in
                      ("key", "url", "sha256", "size", "width", "height", "content_type")}
            for target in targets:
                if original and not target.get("url"):
                    target["url"] = original
                for name, value in stored.items():
                    if name == "orig_url" or value is None:
                        continue
                    # 原条目决定角色；同 URL 的封面/正文/头像不能相互改写。
                    if not is_new and name in ("type", "is_avatar"):
                        continue
                    field = fields.get(name, name)
                    if target.get(field) is None:
                        target[field] = value
    return changed


def upgrade():
    connection = op.get_bind()
    rows = connection.execute(text(
        "SELECT id, archive_metadata FROM contents WHERE archive_metadata IS NOT NULL"
    ))
    for content_id, raw in rows:
        metadata = json.loads(raw)
        if not isinstance(metadata, dict):
            continue
        changed = False
        for name in ("archive", "processed_archive"):
            archive = metadata.get(name)
            if isinstance(archive, dict):
                changed = _merge_archive(archive) or changed
        if changed:
            connection.execute(text(
                "UPDATE contents SET archive_metadata = :metadata WHERE id = :id"
            ), {"metadata": json.dumps(metadata, ensure_ascii=False), "id": content_id})


def downgrade():
    raise RuntimeError("Media archive consolidation is forward-only; restore a database backup to roll back.")
