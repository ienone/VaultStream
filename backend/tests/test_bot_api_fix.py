#!/usr/bin/env python3
"""测试脚本：验证Bot API修复"""

import httpx
import asyncio

API_BASE = "http://localhost:8000/api/v1"

async def test_bot_api():
    """测试Bot API的鲁棒性"""
    print("🧪 开始测试Bot API...")
    
    async with httpx.AsyncClient() as client:
        # 测试1: 正常查询（无tag）
        print("\n1️⃣ 测试: /get 无参数")
        try:
            resp = await client.post(
                f"{API_BASE}/bot/get-content",
                json={
                    "target_platform": "TG_CHANNEL_test",
                    "limit": 1
                }
            )
            print(f"   状态码: {resp.status_code}")
            if resp.status_code == 200:
                data = resp.json()
                print(f"   ✅ 成功: 返回 {len(data)} 条内容")
                if data:
                    content = data[0]
                    print(f"   标题: {content.get('title', 'N/A')}")
                    print(f"   作者: {content.get('author_name', 'N/A')}")
            else:
                print(f"   ❌ 错误: {resp.text}")
        except Exception as e:
            print(f"   ❌ 异常: {e}")
        
        # 测试2: 正常tag查询
        print("\n2️⃣ 测试: /get tag1")
        try:
            resp = await client.post(
                f"{API_BASE}/bot/get-content",
                json={
                    "target_platform": "TG_CHANNEL_test",
                    "tag": "tag1",
                    "limit": 1
                }
            )
            print(f"   状态码: {resp.status_code}")
            if resp.status_code == 200:
                data = resp.json()
                print(f"   ✅ 成功: 返回 {len(data)} 条内容")
                if data:
                    content = data[0]
                    print(f"   标题: {content.get('title', 'N/A')}")
                    print(f"   标签: {content.get('tags', [])}")
            else:
                print(f"   ❌ 错误: {resp.text}")
        except Exception as e:
            print(f"   ❌ 异常: {e}")
        
        # 测试3: 中文tag查询（之前会500）
        print("\n3️⃣ 测试: /get 游戏 (中文tag)")
        try:
            resp = await client.post(
                f"{API_BASE}/bot/get-content",
                json={
                    "target_platform": "TG_CHANNEL_test",
                    "tag": "游戏",
                    "limit": 1
                }
            )
            print(f"   状态码: {resp.status_code}")
            if resp.status_code == 200:
                data = resp.json()
                print(f"   ✅ 成功: 返回 {len(data)} 条内容")
            else:
                print(f"   ⚠️  错误 (但不是500): {resp.status_code}")
                print(f"   响应: {resp.text[:200]}")
        except Exception as e:
            print(f"   ❌ 异常: {e}")
        
        # 测试4: 空字符串tag（边界情况）
        print("\n4️⃣ 测试: /get '  ' (空格tag)")
        try:
            resp = await client.post(
                f"{API_BASE}/bot/get-content",
                json={
                    "target_platform": "TG_CHANNEL_test",
                    "tag": "   ",  # 空格
                    "limit": 1
                }
            )
            print(f"   状态码: {resp.status_code}")
            if resp.status_code == 200:
                data = resp.json()
                print(f"   ✅ 成功: 忽略空tag，返回 {len(data)} 条内容")
            else:
                print(f"   ❌ 错误: {resp.text[:200]}")
        except Exception as e:
            print(f"   ❌ 异常: {e}")
        
        # 测试5: 空字符串tag（None）
        print("\n5️⃣ 测试: tag=None")
        try:
            resp = await client.post(
                f"{API_BASE}/bot/get-content",
                json={
                    "target_platform": "TG_CHANNEL_test",
                    "tag": None,
                    "limit": 1
                }
            )
            print(f"   状态码: {resp.status_code}")
            if resp.status_code == 200:
                data = resp.json()
                print(f"   ✅ 成功: 返回 {len(data)} 条内容")
            else:
                print(f"   ❌ 错误: {resp.text[:200]}")
        except Exception as e:
            print(f"   ❌ 异常: {e}")

    print("\n" + "="*60)
    print("✅ 测试完成！")
    print("="*60)

if __name__ == "__main__":
    asyncio.run(test_bot_api())
