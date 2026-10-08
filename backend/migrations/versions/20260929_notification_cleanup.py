"""Retire delivery reconciliation and duplicate automatic index notices."""
from alembic import op
import sqlalchemy as sa

revision = "20260929_notification_cleanup"
down_revision = "20260928_manual_push"
branch_labels = None
depends_on = None


def upgrade():
    op.drop_index("uq_queue_manual_content_chat", table_name="content_queue_items")
    op.create_index("uq_queue_manual_content_chat", "content_queue_items", ["content_id", "bot_chat_id"],
                    unique=True, sqlite_where=sa.text("rule_id IS NULL AND (last_error_type IS NULL OR last_error_type != 'delivery_unknown')"))
    op.execute(sa.text("""
        UPDATE notification_messages
        SET read_at = COALESCE(read_at, CURRENT_TIMESTAMP),
            dismissed_at = COALESCE(dismissed_at, CURRENT_TIMESTAMP),
            updated_at = CURRENT_TIMESTAMP
        WHERE source_type = 'distribution_delivery'
           OR (source_type = 'background_task_run'
               AND json_extract(payload, '$.task') IN ('content_embedding', 'distribution_worker_poll')
               AND COALESCE(json_extract(payload, '$.metadata.trigger'), '')
                   NOT IN ('manual', 'retry', 'user', 'api'))
    """))
    op.execute(sa.text("""
        UPDATE notification_messages
        SET title = '未收到发送回执', body = '已停止自动重试。', route = NULL
        WHERE source_type = 'distribution_delivery'
    """))


def downgrade():
    # Downgrade fails rather than discarding distinct retained delivery facts.
    op.drop_index("uq_queue_manual_content_chat", table_name="content_queue_items")
    op.create_index("uq_queue_manual_content_chat", "content_queue_items", ["content_id", "bot_chat_id"],
                    unique=True, sqlite_where=sa.text("rule_id IS NULL"))
