"""Normalize stored HTTP identities without discarding independent saved records."""
from alembic import op
import sqlalchemy as sa

revision = "20261114_content_identity"
down_revision = "20261113_embedding_float32"
branch_labels = None
depends_on = None


def upgrade() -> None:
    from app.services.content_identity import canonical_link, InvalidShareInput

    conn = op.get_bind()
    rows = conn.execute(sa.text("""
        SELECT id, platform, url, canonical_url, discovery_state FROM contents
        WHERE canonical_url LIKE 'http://%' OR canonical_url LIKE 'https://%'
        ORDER BY deleted_at IS NOT NULL, discovery_state IS NOT NULL AND discovery_state <> 'promoted', id
    """)).mappings().all()
    claimed = set()
    updates = []
    for row in rows:
        try:
            platform, normalized = canonical_link(row["canonical_url"])
        except (InvalidShareInput, ValueError):
            continue
        identity = (platform.value, normalized)
        # Keep each historical item's ID, annotations and references. Only the
        # primary item owns the lookup key for subsequent saves of the same link.
        canonical = normalized if identity not in claimed else None
        claimed.add(identity)
        if (row["platform"], row["canonical_url"]) != (platform.value, canonical):
            updates.append({"id": row["id"], "platform": platform.value, "canonical": canonical})
    if updates:
        conn.execute(sa.text("UPDATE contents SET canonical_url=NULL WHERE id=:id"), [{"id": x["id"]} for x in updates])
        conn.execute(sa.text("UPDATE contents SET platform=:platform, canonical_url=:canonical WHERE id=:id"), updates)


def downgrade() -> None:
    pass
