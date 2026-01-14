"""
添加 Task 表用于 SQLite 队列模式

Revision ID: add_task_table
Create Date: 2026-01-06

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

# revision identifiers
revision = 'add_task_table'
down_revision = None  # 根据实际情况修改
branch_labels = None
depends_on = None


def upgrade():
    """添加 Task 表"""
    # 检测数据库类型
    bind = op.get_bind()
    dialect = bind.dialect.name
    
    # 根据数据库类型选择 JSON 字段类型
    if dialect == 'postgresql':
        json_type = JSONB
    else:  # sqlite
        json_type = sa.JSON
    
    # 创建 Task 表
    op.create_table(
        'tasks',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('task_type', sa.String(length=100), nullable=False),
        sa.Column('payload', json_type, nullable=False),
        sa.Column('status', sa.Enum('PENDING', 'RUNNING', 'COMPLETED', 'FAILED', name='taskstatus'), nullable=True),
        sa.Column('priority', sa.Integer(), nullable=True),
        sa.Column('retry_count', sa.Integer(), nullable=True),
        sa.Column('max_retries', sa.Integer(), nullable=True),
        sa.Column('last_error', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.Column('started_at', sa.DateTime(), nullable=True),
        sa.Column('completed_at', sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint('id')
    )
    
    # 创建索引
    op.create_index('ix_tasks_status', 'tasks', ['status'], unique=False)
    op.create_index('ix_tasks_priority', 'tasks', ['priority'], unique=False)
    op.create_index('ix_tasks_created_at', 'tasks', ['created_at'], unique=False)
    op.create_index('ix_tasks_id', 'tasks', ['id'], unique=False)


def downgrade():
    """删除 Task 表"""
    op.drop_index('ix_tasks_id', table_name='tasks')
    op.drop_index('ix_tasks_created_at', table_name='tasks')
    op.drop_index('ix_tasks_priority', table_name='tasks')
    op.drop_index('ix_tasks_status', table_name='tasks')
    op.drop_table('tasks')
