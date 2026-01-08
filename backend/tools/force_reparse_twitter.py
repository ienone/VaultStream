import asyncio
import sys
import os

# Add backend root to sys.path to allow imports from app
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import select
from app.database import init_db, AsyncSessionLocal
from app.models import Content, Platform, ContentStatus
from app.queue import task_queue
from app.logging import logger

async def main():
    print("开始执行推特数据强制重解析任务...")
    print("此操作将重置所有推特内容的状态并重新触发解析，以应用最新的元数据结构。")
    
    # 1. 初始化
    await init_db()
    await task_queue.connect()
    
    async with AsyncSessionLocal() as session:
        # 2. 查询所有 Twitter 内容
        stmt = select(Content).where(Content.platform == Platform.TWITTER)
        result = await session.execute(stmt)
        contents = result.scalars().all()
        
        total = len(contents)
        print(f"找到 {total} 条推特内容待处理。")
        
        if total == 0:
            print("没有找到推特内容，退出。")
            return

        # 3. 逐条重置状态并入队
        # 为了避免长时间锁定数据库，逐个提交
        for i, content in enumerate(contents, 1):
            try:
                # 关键步骤：重置状态为 UNPROCESSED
                # 这会强制 Worker 认为这是一条新任务，从而绕过“已完成跳过”的检查
                old_status = content.status
                content.status = ContentStatus.UNPROCESSED
                
                # 提交状态更改
                session.add(content)
                await session.commit()
                
                # 入队新任务
                await task_queue.enqueue({
                    "content_id": content.id,
                    "action": "parse",
                    "force_update": True, # 语义标识
                    "schema_version": 1
                })
                
                print(f"[{i}/{total}] 重置 ID={content.id} (原状态: {old_status}) -> 已入队")
            except Exception as e:
                print(f"[{i}/{total}] 处理 ID={content.id} 时出错: {e}")

    print("-" * 50)
    print(f"所有 {total} 个任务已重新入队。")
    print("Worker 后台将会逐个重新下载数据、清洗元数据并补全缺失的图片。")
    print("请确保 .env 代理配置正确，否则图片下载可能会失败。")
    await task_queue.disconnect()

if __name__ == "__main__":
    if sys.platform == 'win32':
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    asyncio.run(main())
