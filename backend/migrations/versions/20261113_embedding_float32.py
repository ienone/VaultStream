"""Store existing embedding vectors as compact float32 values."""

from alembic import op
import sqlalchemy as sa


revision = "20261113_embedding_float32"
down_revision = "20260929_notification_cleanup"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        UPDATE content_embeddings SET embedding = CASE
            WHEN json_array_length(embedding) = 0 THEN X''
            ELSE vec_f32(embedding)
        END
    """)
    with op.batch_alter_table("content_embeddings") as batch:
        batch.alter_column("embedding", existing_type=sa.JSON(), type_=sa.LargeBinary(),
                           existing_nullable=False)


def downgrade() -> None:
    op.execute("""
        UPDATE content_embeddings SET embedding = CASE
            WHEN length(embedding) = 0 THEN '[]'
            ELSE vec_to_json(embedding)
        END
    """)
    with op.batch_alter_table("content_embeddings") as batch:
        batch.alter_column("embedding", existing_type=sa.LargeBinary(), type_=sa.JSON(),
                           existing_nullable=False)
