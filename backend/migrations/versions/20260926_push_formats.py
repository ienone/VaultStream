"""Replace field-by-field message templates with three push formats."""
import json
from alembic import op
import sqlalchemy as sa

revision = '20260926_push_formats'
down_revision = '20260925_telegram_messages'
branch_labels = None
depends_on = None


def upgrade():
    connection = op.get_bind()
    for table, field in [('distribution_rules', 'render_config')]:
        for row_id, raw in connection.execute(sa.text(f'SELECT id, {field} FROM {table}')):
            config = json.loads(raw) if isinstance(raw, str) else raw
            if not config:
                continue
            old = config.get('structure', config)
            mode = 'text' if old.get('media_mode') == 'none' else (
                'full' if old.get('content_mode') == 'full' or old.get('media_mode') == 'all' else 'summary')
            connection.execute(sa.text(f'UPDATE {table} SET {field}=:config WHERE id=:id'),
                               {'id': row_id, 'config': json.dumps({'format': mode})})


def downgrade():
    pass
