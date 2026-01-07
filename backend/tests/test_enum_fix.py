"""
测试 ReviewStatus enum 修复
"""
import sys
sys.path.insert(0, '.')

import asyncio
from app.database import AsyncSessionLocal
from app.models import Content, ReviewStatus
from app.schemas import ContentDetail
from sqlalchemy import select


async def test_review_status():
    """测试 review_status 读取"""
    print("=" * 60)
    print("测试 ReviewStatus enum 修复")
    print("=" * 60)
    
    async with AsyncSessionLocal() as db:
        # 1. 测试读取
        result = await db.execute(select(Content).limit(3))
        contents = result.scalars().all()
        
        print(f"\n✅ 成功读取 {len(contents)} 条内容")
        
        for content in contents:
            print(f"\n内容 ID {content.id}:")
            print(f"  - review_status: {content.review_status} (类型: {type(content.review_status).__name__})")
            print(f"  - tags: {content.tags} (类型: {type(content.tags).__name__})")
            
            # 2. 测试 Pydantic 验证
            try:
                detail = ContentDetail.model_validate(content)
                print(f"  ✅ Pydantic 验证成功")
            except Exception as e:
                print(f"  ❌ Pydantic 验证失败: {e}")
                return
        
        # 3. 测试枚举值
        print(f"\n\nReviewStatus 枚举值:")
        for status in ReviewStatus:
            print(f"  - {status.name} = '{status.value}'")
        
        print("\n" + "=" * 60)
        print("所有测试通过！")
        print("=" * 60)


if __name__ == "__main__":
    asyncio.run(test_review_status())
