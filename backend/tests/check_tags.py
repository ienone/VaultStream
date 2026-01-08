#!/usr/bin/env python3
"""检查数据库中的tags存储情况"""
import asyncio
import sys
from ypathlib import Path

# Add the project root to the path
sys.path.insert(0, str(Path(__file__).parent))

from app.database import AsyncSessionLocal
from app.models import Content
from sqlalchemy import select


async def check_tags():
    async with AsyncSessionLocal() as session:
        # 查询最近的10条记录
        query = select(Content).order_by(Content.created_at.desc()).limit(10)
        result = await session.execute(query)
        contents = result.scalars().all()
        
        print("=" * 80)
        print("数据库中最近的10条内容：")
        print("=" * 80)
        
        for content in contents:
            print(f"\nID: {content.id}")
            print(f"URL: {content.url}")
            print(f"标题: {content.title or '未设置'}")
            print(f"作者: {content.author_name or '未知'} (ID: {content.author_id or 'N/A'})")
            print(f"Tags类型: {type(content.tags)}")
            print(f"Tags内容: {content.tags}")
            print(f"Tags长度: {len(content.tags) if content.tags else 0}")
            print(f"创建时间: {content.created_at}")
            print("-" * 80)
        
        # 统计有tags的内容
        query_with_tags = select(Content).where(Content.tags.isnot(None))
        result = await session.execute(query_with_tags)
        contents_with_tags = result.scalars().all()
        
        print(f"\n总共有 {len(contents_with_tags)} 条内容包含tags")
        
        # 查询包含特定tag的内容（测试查询逻辑）
        test_tag = "游戏"
        query_game = select(Content).where(Content.tags.contains([test_tag]))
        result = await session.execute(query_game)
        game_contents = result.scalars().all()
        
        print(f"包含tag '{test_tag}' 的内容数量: {len(game_contents)}")
        if game_contents:
            print("\n包含'游戏'tag的内容:")
            for content in game_contents[:5]:  # 只显示前5个
                print(f"  - {content.title} (tags: {content.tags})")


if __name__ == "__main__":
    asyncio.run(check_tags())
