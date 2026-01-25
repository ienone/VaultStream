import asyncio
import sys
import os
from loguru import logger

# Add backend directory to sys.path
sys.path.append(os.path.join(os.getcwd(), "backend"))

from app.adapters.zhihu import ZhihuAdapter

COOKE_STR = os.getenv("ZHIHU_COOKIE", "")

async def test_url(adapter, url, label):
    """Test parsing a URL through the adapter"""
    print(f"\n--- Testing {label} ---")
    print(f"URL: {url}")
    try:
        result = await adapter.parse(url)
        print(f"SUCCESS: Title='{result.title}'")
        print(f"Type: {result.content_type}")
        if hasattr(result, 'author') and result.author:
            print(f"Author: {result.author}")
        if hasattr(result, 'stats') and result.stats:
            print(f"Stats: {result.stats}")
        return True
    except Exception as e:
        print(f"ERROR: {e}")
        return False

async def main():
    cookies = {}
    if COOKE_STR:
        for item in COOKE_STR.split(';'):
            if '=' in item:
                k, v = item.strip().split('=', 1)
                cookies[k] = v
    
    adapter = ZhihuAdapter(cookies=cookies)
    
    # Test cases covering different content types
    test_cases = [
        ("https://www.zhihu.com/question/1993325945164166141/answer/1993398155283284591", "Answer"),
        ("https://zhuanlan.zhihu.com/p/676348421", "Article"),
        ("https://www.zhihu.com/question/532925796", "Question"),
        ("https://www.zhihu.com/people/excited-vczh", "User Profile"),
    ]
    
    print("="*60)
    print("ZHIHU ADAPTER TEST")
    print("="*60)
    
    results = {}
    for url, label in test_cases:
        success = await test_url(adapter, url, label)
        results[label] = "✅ PASS" if success else "❌ FAIL"
        await asyncio.sleep(1)
    
    print("\n" + "="*60)
    print("FINAL SUMMARY")
    print("="*60)
    for label, result in results.items():
        print(f"{label:20s}: {result}")

if __name__ == "__main__":
    asyncio.run(main())
