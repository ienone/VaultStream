"""Keep the effective text model address and discard unused sync options."""
from alembic import op
import json
import sqlalchemy as sa


revision = "20261114_settings_keys"
down_revision = "20261114_delivery_receipt"
branch_labels = None
depends_on = None


def upgrade():
    # The reader used the old editor key only when the canonical value was empty.
    op.execute("""
        DELETE FROM system_settings WHERE key = 'text_llm_base_url'
          AND COALESCE(json_extract(value, '$'), '') = ''
          AND EXISTS (SELECT 1 FROM system_settings WHERE key = 'text_llm_api_base')
    """)
    op.execute("""
        UPDATE OR IGNORE system_settings SET key = 'text_llm_base_url'
        WHERE key = 'text_llm_api_base'
    """)
    op.execute("""
        DELETE FROM system_settings WHERE key IN (
          'text_llm_api_base', 'favorites_sync_scope_strategy',
          'favorites_sync_first_sync_strategy', 'favorites_sync_unfavorite_strategy',
          'qq_admin_ids', 'qq_whitelist_ids', 'qq_blacklist_ids'
        )
    """)

    # The manual editor formerly stored each part separately, while QR saved a complete header.
    conn = op.get_bind()
    parts = {k: json.loads(v) for k, v in conn.execute(sa.text("""
        SELECT key, value FROM system_settings
        WHERE key IN ('bilibili_cookie','bilibili_bili_jct','bilibili_buvid3')
    """))}
    header = str(parts.get("bilibili_cookie") or "").strip().strip("'\"")
    if header and not header.startswith("***"):
        if "=" not in header:
            header = "SESSDATA=" + header
        cookies = {name.strip(): value.strip() for item in header.split(";")
                   if "=" in item for name, value in [item.split("=", 1)]}
        for name in ("bili_jct", "buvid3"):
            value = parts.get(f"bilibili_{name}")
            if value and not str(value).startswith("***"):
                cookies.setdefault(name, str(value))
        if cookies.get("SESSDATA"):
            conn.execute(sa.text("UPDATE system_settings SET value=:value WHERE key='bilibili_cookie'"),
                         {"value": json.dumps("; ".join(f"{k}={v}" for k, v in cookies.items()))})
            op.execute("DELETE FROM system_settings WHERE key IN ('bilibili_bili_jct','bilibili_buvid3')")


def downgrade():
    # Older versions already read the canonical address.
    pass
