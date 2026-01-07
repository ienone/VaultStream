#!/usr/bin/env python3
"""
重试失败的任务

将 FAILED 状态的内容重置为 UNPROCESSED 并重新入队
"""
import asyncio
import sys
from pathlib import Path

project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

from sqlalchemy import select
from app.database import AsyncSessionLocal
from app.models import Content, ContentStatus, Platform
from app.queue import task_queue
from app.logging import logger


async def retry_failed_tasks(platform: str = None, limit: int = 100):
    """
    重试失败的任务
    
    Args:
        platform: 平台过滤（可选），如 'twitter', 'bilibili'
        limit: 最多重试数量
    """
    async with AsyncSessionLocal() as db:
        # 查询失败的内容
        query = select(Content).where(Content.status == ContentStatus.FAILED)
        
        if platform:
            try:
                platform_enum = Platform(platform)
                query = query.where(Content.platform == platform_enum)
            except ValueError:
                print(f"✗ 无效的平台: {platform}")
                return
        
        query = query.order_by(Content.created_at.desc()).limit(limit)
        
        result = await db.execute(query)
        failed_contents = result.scalars().all()
        
        if not failed_contents:
            print("✓ 没有需要重试的失败任务")
            return
        
        print(f"找到 {len(failed_contents)} 个失败任务")
        print("=" * 70)
        
        retry_count = 0
        
        for content in failed_contents:
            print(f"\nID: {content.id}")
            print(f"  平台: {content.platform}")
            print(f"  URL: {content.url}")
            print(f"  失败次数: {content.failure_count}")
            print(f"  错误类型: {content.last_error_type}")
            print(f"  错误: {content.last_error[:100] if content.last_error else 'N/A'}")
            
            # 重置状态
            content.status = ContentStatus.UNPROCESSED
            content.failure_count = 0
            content.last_error = None
            content.last_error_type = None
            content.last_error_detail = None
            content.last_error_at = None
            
            # 重新入队
            try:
                await task_queue.enqueue({
                    "schema": 1,
                    "action": "parse",
                    "content_id": content.id,
                })
                print(f"  ✓ 已重新入队")
                retry_count += 1
            except Exception as e:
                print(f"  ✗ 入队失败: {e}")
        
        # 提交更改
        await db.commit()
        
        print()
        print("=" * 70)
        print(f"✓ 成功重试 {retry_count} 个任务")
        print()
        print("提示:")
        print("  - 确保 worker 正在运行: python3 -m app.worker")
        print("  - 查看 worker 日志确认处理进度")


async def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="重试失败的任务")
    parser.add_argument(
        "--platform",
        choices=["twitter", "bilibili"],
        help="只重试指定平台的任务"
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=100,
        help="最多重试数量（默认 100）"
    )
    
    args = parser.parse_args()
    
    print("=" * 70)
    print("重试失败任务")
    print("=" * 70)
    print()
    
    if args.platform:
        print(f"平台筛选: {args.platform}")
    print(f"最大数量: {args.limit}")
    print()
    
    await retry_failed_tasks(platform=args.platform, limit=args.limit)


if __name__ == '__main__':
    asyncio.run(main())
