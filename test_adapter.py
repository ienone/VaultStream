"""
测试脚本 - 测试B站适配器和完整流程
"""
import asyncio
from app.adapters.bilibili import BilibiliAdapter


async def test_bilibili_adapter():
    """测试B站适配器"""
    adapter = BilibiliAdapter()
    
    # 测试URL列表
    test_urls = [
        "https://www.bilibili.com/video/BV1xx411c7XD",  # 视频
        "https://www.bilibili.com/read/cv12345678",     # 专栏
        "https://www.bilibili.com/opus/1150580721704763430",       # 动态
    ]
    
    for url in test_urls:
        print(f"\n{'='*60}")
        print(f"测试URL: {url}")
        print(f"{'='*60}")
        
        try:
            # 检测内容类型
            content_type = await adapter.detect_content_type(url)
            print(f"✅ 内容类型: {content_type}")
            
            # 净化URL
            clean_url = await adapter.clean_url(url)
            print(f"✅ 净化URL: {clean_url}")
            
            # 解析内容（可能会失败，因为ID是示例）
            try:
                parsed = await adapter.parse(url)
                print(f"✅ 标题: {parsed.title}")
                print(f"✅ 作者: {parsed.author_name}")
                print(f"✅ 描述: {parsed.description[:100] if parsed.description else 'N/A'}...")
                print(f"✅ 封面: {parsed.cover_url}")
            except Exception as e:
                print(f"⚠️  解析失败（预期，因为是示例ID）: {e}")
                
        except Exception as e:
            print(f"❌ 错误: {e}")


async def test_real_url():
    """测试真实URL（需要手动提供）"""
    adapter = BilibiliAdapter()
    
    # 这里放一个真实的B站URL
    real_url = input("\n请输入一个真实的B站URL进行测试（直接回车跳过）: ").strip()
    
    if not real_url:
        print("跳过真实URL测试")
        return
    
    try:
        print(f"\n{'='*60}")
        print(f"解析真实URL: {real_url}")
        print(f"{'='*60}")
        
        parsed = await adapter.parse(real_url)
        
        print(f"\n📊 解析结果:")
        print(f"  平台: {parsed.platform}")
        print(f"  类型: {parsed.content_type}")
        print(f"  ID: {parsed.content_id}")
        print(f"  标题: {parsed.title}")
        print(f"  作者: {parsed.author_name} (ID: {parsed.author_id})")
        print(f"  描述: {parsed.description[:200] if parsed.description else 'N/A'}...")
        print(f"  封面: {parsed.cover_url}")
        print(f"  媒体数: {len(parsed.media_urls)}")
        print(f"\n  元数据:")
        for key, value in parsed.raw_metadata.items():
            print(f"    {key}: {value}")
            
        print(f"\n✅ 解析成功！")
        
    except Exception as e:
        print(f"❌ 解析失败: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    print("🧪 VaultStream - B站适配器测试")
    print("="*60)
    
    # 运行测试
    asyncio.run(test_bilibili_adapter())
    asyncio.run(test_real_url())
    
    print("\n✨ 测试完成！")
