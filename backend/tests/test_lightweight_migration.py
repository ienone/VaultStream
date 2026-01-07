#!/usr/bin/env python3
"""
轻量模式迁移验证脚本
"""
import asyncio
import os
import sys

# 添加项目路径
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

async def test_database():
    """测试数据库连接"""
    print("🧪 测试数据库连接...")
    
    from app.config import settings
    from app.database import init_db, db_ping
    
    print(f"   数据库类型: {settings.database_type}")
    if settings.database_type == "sqlite":
        print(f"   SQLite 路径: {settings.sqlite_db_path}")
    
    # 初始化数据库
    await init_db()
    print("   ✅ 数据库初始化成功")
    
    # 健康检查
    is_healthy = await db_ping()
    if is_healthy:
        print("   ✅ 数据库连接正常")
    else:
        print("   ❌ 数据库连接失败")
        return False
    
    return True


async def test_queue():
    """测试队列"""
    print("\n🧪 测试任务队列...")
    
    from app.config import settings
    from app.queue import task_queue
    
    print(f"   队列类型: {settings.queue_type}")
    
    # 连接队列
    await task_queue.connect()
    print("   ✅ 队列连接成功")
    
    # 健康检查
    is_healthy = await task_queue.ping()
    if is_healthy:
        print("   ✅ 队列连接正常")
    else:
        print("   ❌ 队列连接失败")
        await task_queue.disconnect()
        return False
    
    # 测试入队出队
    test_task = {
        "content_id": 999,
        "action": "parse",
        "task_id": "test_task_001"
    }
    
    success = await task_queue.enqueue(test_task)
    if success:
        print("   ✅ 任务入队成功")
    else:
        print("   ❌ 任务入队失败")
        await task_queue.disconnect()
        return False
    
    task = await task_queue.dequeue(timeout=2)
    if task and task.get("content_id") == 999:
        print("   ✅ 任务出队成功")
        await task_queue.mark_complete(999)
    else:
        print("   ❌ 任务出队失败")
        await task_queue.disconnect()
        return False
    
    await task_queue.disconnect()
    return True


async def test_storage():
    """测试存储"""
    print("\n🧪 测试对象存储...")
    
    from app.config import settings
    from app.storage import get_storage_backend
    import hashlib
    
    print(f"   存储类型: {settings.storage_backend}")
    if settings.storage_backend == "local":
        print(f"   本地路径: {settings.storage_local_root}")
    
    storage = get_storage_backend()
    
    # 测试存储对象
    test_data = b"Hello VaultStream!"
    test_hash = hashlib.sha256(test_data).hexdigest()
    test_key = f"sha256:{test_hash}"
    
    # 存储
    obj = await storage.put_bytes(
        key=test_key,
        data=test_data,
        content_type="text/plain"
    )
    print(f"   ✅ 对象存储成功: {obj.key}")
    
    # 检查存在性
    exists = await storage.exists(key=test_key)
    if exists:
        print("   ✅ 对象存在性检查通过")
    else:
        print("   ❌ 对象存在性检查失败")
        return False
    
    # 获取 URL
    url = storage.get_url(key=test_key)
    if url:
        print(f"   ✅ 对象 URL: {url}")
    else:
        print("   ℹ️  对象 URL 未配置")
    
    return True


async def test_models():
    """测试数据模型"""
    print("\n🧪 测试数据模型...")
    
    from app.database import AsyncSessionLocal
    from app.models import Content, Platform, ContentStatus, Task, TaskStatus
    from sqlalchemy import select
    
    async with AsyncSessionLocal() as session:
        # 测试 Content 表
        stmt = select(Content).limit(1)
        result = await session.execute(stmt)
        print("   ✅ Content 表查询正常")
        
        # 测试 Task 表
        stmt = select(Task).limit(1)
        result = await session.execute(stmt)
        print("   ✅ Task 表查询正常")
    
    return True


async def main():
    """主测试函数"""
    print("=" * 60)
    print("VaultStream 轻量模式迁移验证")
    print("=" * 60)
    
    try:
        # 测试数据库
        if not await test_database():
            print("\n❌ 数据库测试失败")
            return False
        
        # 测试队列
        if not await test_queue():
            print("\n❌ 队列测试失败")
            return False
        
        # 测试存储
        if not await test_storage():
            print("\n❌ 存储测试失败")
            return False
        
        # 测试数据模型
        if not await test_models():
            print("\n❌ 数据模型测试失败")
            return False
        
        print("\n" + "=" * 60)
        print("✅ 所有测试通过！轻量模式迁移成功！")
        print("=" * 60)
        print("\n💡 提示：")
        print("   - 数据库文件: ./data/vaultstream.db")
        print("   - 媒体存储: ./data/media/")
        print("   - 启动服务: ./start.sh")
        print("=" * 60)
        
        return True
        
    except Exception as e:
        print(f"\n❌ 测试失败: {e}")
        import traceback
        traceback.print_exc()
        return False


if __name__ == "__main__":
    success = asyncio.run(main())
    sys.exit(0 if success else 1)
