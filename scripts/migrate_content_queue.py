"""
数据库迁移脚本：创建 content_queue_items 表

用法：
    cd backend
    python ../scripts/migrate_content_queue.py

功能：
    1. 创建 content_queue_items 表（如果不存在）
    2. 为已审批的 pulled 内容自动创建队列项（回填）
"""
import asyncio
import sys
import os

# 添加 backend 目录到 Python 路径
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'backend'))

from sqlalchemy import text, select, inspect
from app.core.db_adapter import engine, AsyncSessionLocal
from app.models import Base, Content, ContentStatus, ReviewStatus, ContentQueueItem


async def create_table():
    """创建 content_queue_items 表"""
    async with engine.begin() as conn:
        # 检查表是否已存在
        def check_table(sync_conn):
            insp = inspect(sync_conn)
            return insp.has_table("content_queue_items")
        
        exists = await conn.run_sync(check_table)
        if exists:
            print("✅ content_queue_items 表已存在，跳过创建")
            return False
        
        # 只创建新表
        await conn.run_sync(Base.metadata.create_all, tables=[ContentQueueItem.__table__])
        print("✅ content_queue_items 表已创建")
        return True


async def backfill_queue_items():
    """为已审批的 pulled 内容回填队列项"""
    from app.distribution.queue_service import enqueue_content
    
    async with AsyncSessionLocal() as session:
        result = await session.execute(
            select(Content).where(
                Content.status == ContentStatus.PULLED,
                Content.review_status.in_([
                    ReviewStatus.APPROVED,
                    ReviewStatus.AUTO_APPROVED,
                ]),
            ).order_by(Content.created_at.desc()).limit(500)
        )
        contents = result.scalars().all()
        
        if not contents:
            print("📭 没有需要回填的内容")
            return
        
        print(f"📦 开始回填 {len(contents)} 条内容...")
        
        total_enqueued = 0
        for i, content in enumerate(contents):
            try:
                count = await enqueue_content(content.id, session=session)
                total_enqueued += count
                if (i + 1) % 50 == 0:
                    print(f"  进度: {i + 1}/{len(contents)}, 已入队: {total_enqueued}")
            except Exception as e:
                print(f"  ⚠️ 回填失败 content_id={content.id}: {e}")
        
        print(f"✅ 回填完成: {total_enqueued} 个队列项已创建")


async def main():
    print("=" * 60)
    print("VaultStream 分发队列迁移脚本")
    print("=" * 60)
    
    # 1. 创建表
    created = await create_table()
    
    # 2. 回填
    if "--backfill" in sys.argv or created:
        await backfill_queue_items()
    else:
        print("💡 使用 --backfill 参数可回填已有内容到队列")
    
    print("\n✅ 迁移完成")


if __name__ == "__main__":
    asyncio.run(main())
