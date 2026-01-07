#!/usr/bin/env python3
"""
测试 M5 自动推送功能
"""
import asyncio
import sys
sys.path.insert(0, '/home/deng-shengxi/文档/VaultStream')

from app.database import AsyncSessionLocal
from app.models import Content, DistributionRule, ReviewStatus
from app.queue import task_queue
from sqlalchemy import select


async def test_distribution():
    """测试分发功能"""
    print("=" * 60)
    print("M5 自动推送功能测试")
    print("=" * 60)
    
    # 连接数据库
    await task_queue.connect()
    
    async with AsyncSessionLocal() as session:
        # 1. 检查是否有 approved 的内容
        result = await session.execute(
            select(Content)
            .where(Content.review_status.in_([ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]))
            .limit(5)
        )
        contents = result.scalars().all()
        
        print(f"\n✓ 找到 {len(contents)} 条已批准的内容")
        for content in contents:
            print(f"  - ID: {content.id}, 标题: {content.title[:50] if content.title else 'N/A'}")
        
        # 2. 检查分发规则
        result = await session.execute(
            select(DistributionRule).where(DistributionRule.enabled == True)
        )
        rules = result.scalars().all()
        
        print(f"\n✓ 找到 {len(rules)} 条启用的分发规则")
        for rule in rules:
            print(f"  - ID: {rule.id}, 名称: {rule.name}")
            print(f"    匹配条件: {rule.match_conditions}")
            print(f"    目标数量: {len(rule.targets or [])}")
        
        # 3. 模拟创建一个分发任务
        if contents and rules:
            content = contents[0]
            rule = rules[0]
            targets = rule.targets or []
            
            if targets:
                target = targets[0]
                task_data = {
                    "action": "distribute",
                    "content_id": content.id,
                    "rule_id": rule.id,
                    "target_platform": target.get("platform", "telegram"),
                    "target_id": target.get("target_id"),
                    "schema_version": 2
                }
                
                await task_queue.enqueue(task_data)
                print(f"\n✓ 已创建测试分发任务:")
                print(f"  内容ID: {content.id}")
                print(f"  规则ID: {rule.id}")
                print(f"  目标: {target.get('target_id')}")
        
        print("\n" + "=" * 60)
        print("测试完成！")
        print("提示：")
        print("1. 确保后端服务正在运行 (uvicorn)")
        print("2. 分发调度器会在1分钟内处理此任务")
        print("3. Worker 会实际调用 Telegram API 发送消息")
        print("=" * 60)
    
    await task_queue.disconnect()


if __name__ == "__main__":
    asyncio.run(test_distribution())
