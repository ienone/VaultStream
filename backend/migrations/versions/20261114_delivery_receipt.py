"""Distinguish identical recipient IDs on different push platforms."""
from alembic import op


revision = "20261114_delivery_receipt"
down_revision = "20261114_content_identity"
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table("pushed_records") as batch:
        batch.drop_constraint("uq_pushed_records_content_target", type_="unique")
        batch.create_unique_constraint("uq_pushed_records_delivery", ["content_id", "target_platform", "target_id"])
    op.execute("UPDATE content_queue_items SET approved_by='manual' WHERE rule_id IS NULL AND approved_by='explicit_push'")


def downgrade():
    with op.batch_alter_table("pushed_records") as batch:
        batch.drop_constraint("uq_pushed_records_delivery", type_="unique")
        batch.create_unique_constraint("uq_pushed_records_content_target", ["content_id", "target_id"])
