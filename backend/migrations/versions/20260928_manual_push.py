"""Allow explicit sends without manufacturing an automatic rule."""
from alembic import op
import sqlalchemy as sa

revision = "20260928_manual_push"
down_revision = "20260926_push_formats"
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table("content_queue_items") as batch:
        batch.alter_column("rule_id", existing_type=sa.Integer(), nullable=True)
        batch.create_index("uq_queue_manual_content_chat", ["content_id", "bot_chat_id"],
                           unique=True, sqlite_where=sa.text("rule_id IS NULL"))


def downgrade():
    connection = op.get_bind()
    if connection.scalar(sa.text("SELECT count(*) FROM content_queue_items WHERE rule_id IS NULL")):
        raise RuntimeError("Manual deliveries exist; cannot restore a required rule_id")
    with op.batch_alter_table("content_queue_items") as batch:
        batch.drop_index("uq_queue_manual_content_chat")
        batch.alter_column("rule_id", existing_type=sa.Integer(), nullable=False)
