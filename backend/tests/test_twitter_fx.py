#!/usr/bin/env python
"""
测试 FxTwitter API 适配器

无需登录/cookies，通过 FxTwitter API 获取推文内容
"""
import asyncio
import sys
from pathlib import Path

# 添加项目根目录到 Python 路径
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

from app.adapters.twitter_fx import TwitterFxAdapter


async def test_fxtwitter_adapter():
    """测试 FxTwitter 适配器"""
    print("=" * 70)
    print("FxTwitter API 适配器测试")
    print("=" * 70)
    print()
    
    # 测试 URL 列表
    test_urls = [
        "https://x.com/Zhane_Star/status/2007280004393251012?s=20", # 纯文本
        "https://x.com/elonmusk/status/2007518880218886635", # 文本+图片
        "https://x.com/AnimeTrends_/status/2007665313106837861?s=20", # 纯图片+参数
        "https://x.com/milia_2222/status/2007402245911167291?s=20", # 文本+图+视频
        "https://x.com/komoshuai/status/2007759834884821284?s=20", # 文本+多图
        "https://x.com/tsukiato_neko/status/2007712065595813930?s=20", # 文本+视频
        "https://x.com/adelheidx333/status/2003899516735705113?s=20", # 文本+GIF
    ]
    
    adapter = TwitterFxAdapter()
    
    for i, url in enumerate(test_urls, 1):
        print(f"\n[测试 {i}/{len(test_urls)}]")
        print(f"URL: {url}")
        print()
        
        try:
            # 检查是否可以处理
            can_handle = await adapter.can_handle(url)
            print(f"  ✅ 可以处理: {can_handle}")
            
            if not can_handle:
                print("  ⚠️  跳过（无法处理此 URL）")
                continue
            
            # 解析内容
            print("  正在解析...")
            result = await adapter.parse(url)
            
            # 显示结果
            print()
            print("  📄 解析结果:")
            print(f"    平台: {result.platform}")
            print(f"    类型: {result.content_type}")
            print(f"    标题: {result.title}")
            print(f"    作者: {result.author_name} (@{result.author_id})")
            print(f"    发布时间: {result.published_at}")
            print()
            print(f"    内容预览:")
            desc_lines = result.description.split('\n')
            for line in desc_lines[:3]:  # 只显示前3行
                print(f"      {line}")
            if len(desc_lines) > 3:
                print(f"      ... (共 {len(desc_lines)} 行)")
            
            # 显示媒体信息
            media = result.raw_metadata.get("media", [])
            if media:
                print()
                print(f"    媒体 ({len(media)} 个):")
                for j, m in enumerate(media, 1):
                    print(f"      {j}. {m['type']}: {m['url'][:60]}...")
            
            # 显示统计信息
            stats = result.raw_metadata.get("stats", {})
            if stats:
                print()
                print(f"    统计:")
                print(f"      回复: {stats.get('replies', 'N/A')}")
                print(f"      转推: {stats.get('retweets', 'N/A')}")
                print(f"      点赞: {stats.get('likes', 'N/A')}")
                print(f"      浏览: {stats.get('views', 'N/A')}")
            
            print()
            print("  ✅ 解析成功")
            
        except Exception as e:
            print()
            print(f"  ❌ 解析失败: {type(e).__name__}")
            print(f"     错误信息: {str(e)}")
            import traceback
            traceback.print_exc()
        
        print()
        print("-" * 70)
    
    print()
    print("=" * 70)
    print("测试完成")
    print("=" * 70)


if __name__ == '__main__':
    asyncio.run(test_fxtwitter_adapter())
