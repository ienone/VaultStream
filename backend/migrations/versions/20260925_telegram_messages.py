"""Track Telegram occurrences without protecting transient candidates from TTL."""
from alembic import op
import sqlalchemy as sa

revision = '20260925_telegram_messages'
down_revision = '20260920_single_facts'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('telegram_messages',
        sa.Column('account_id', sa.BigInteger(), primary_key=True),
        sa.Column('peer_id', sa.BigInteger(), primary_key=True),
        sa.Column('message_id', sa.BigInteger(), primary_key=True),
        sa.Column('content_id', sa.Integer(), sa.ForeignKey('contents.id', ondelete='CASCADE'), nullable=False),
        sa.Column('fingerprint', sa.String(64), nullable=False),
        sa.Column('origin', sa.JSON(), nullable=True),
    )
    op.create_index('ix_telegram_messages_content_id', 'telegram_messages', ['content_id'])
    op.create_index('ix_telegram_messages_account_fingerprint', 'telegram_messages', ['account_id', 'fingerprint'])


def downgrade():
    op.drop_table('telegram_messages')
