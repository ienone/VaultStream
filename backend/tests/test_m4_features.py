"""
M4 功能测试脚本
测试分发规则、审批流程和推送记录功能
"""
import asyncio
import httpx
import json

BASE_URL = "http://localhost:8000/api/v1"
API_TOKEN = "dev-token-12345"  # 从 .env 中获取

async def test_m4_features():
    """测试 M4 核心功能"""
    
    headers = {"X-API-Token": API_TOKEN}
    
    async with httpx.AsyncClient(timeout=30.0) as client:
        print("=" * 60)
        print("M4 功能测试")
        print("=" * 60)
        
        # 1. 创建分发规则
        print("\n1. 创建分发规则...")
        rule_data = {
            "name": "测试规则-Tech内容推送",
            "description": "将tech标签的内容推送到测试频道",
            "match_conditions": {
                "tags": ["tech", "programming"],
                "is_nsfw": False
            },
            "targets": [
                {
                    "platform": "telegram",
                    "target_id": "@test_channel",
                    "enabled": True
                }
            ],
            "enabled": True,
            "priority": 10,
            "nsfw_policy": "block",
            "approval_required": False,
            "auto_approve_conditions": {
                "is_nsfw": False
            },
            "rate_limit": 10,
            "time_window": 3600
        }
        
        try:
            response = await client.post(
                f"{BASE_URL}/distribution-rules",
                json=rule_data,
                headers=headers
            )
            if response.status_code == 200:
                rule = response.json()
                print(f"✓ 规则创建成功: {rule['name']} (ID: {rule['id']})")
                rule_id = rule['id']
            else:
                print(f"✗ 规则创建失败: {response.status_code} - {response.text}")
                return
        except Exception as e:
            print(f"✗ 请求失败: {e}")
            return
        
        # 2. 获取所有规则
        print("\n2. 获取所有分发规则...")
        try:
            response = await client.get(
                f"{BASE_URL}/distribution-rules",
                headers=headers
            )
            if response.status_code == 200:
                rules = response.json()
                print(f"✓ 共有 {len(rules)} 条规则")
                for r in rules:
                    print(f"  - {r['name']} (优先级: {r['priority']}, 启用: {r['enabled']})")
            else:
                print(f"✗ 获取规则失败: {response.status_code}")
        except Exception as e:
            print(f"✗ 请求失败: {e}")
        
        # 3. 获取待审批内容
        print("\n3. 获取待审批内容...")
        try:
            response = await client.get(
                f"{BASE_URL}/contents/pending-review",
                headers=headers,
                params={"page": 1, "size": 5}
            )
            if response.status_code == 200:
                result = response.json()
                print(f"✓ 待审批内容: {result['total']} 条")
                for item in result['items']:
                    print(f"  - ID:{item['id']} - {item.get('title', 'N/A')} (状态: {item.get('review_status')})")
            else:
                print(f"✗ 获取待审批内容失败: {response.status_code}")
        except Exception as e:
            print(f"✗ 请求失败: {e}")
        
        # 4. 测试内容预览（假设有内容ID=1）
        print("\n4. 测试内容预览...")
        try:
            response = await client.get(
                f"{BASE_URL}/contents/1/preview",
                headers=headers
            )
            if response.status_code == 200:
                preview = response.json()
                print(f"✓ 预览成功:")
                print(f"  标题: {preview.get('title')}")
                print(f"  摘要: {preview.get('summary', 'N/A')[:50]}...")
                print(f"  媒体数量: {len(preview.get('optimized_media', []))}")
            elif response.status_code == 404:
                print("✗ 内容不存在（ID=1），跳过预览测试")
            else:
                print(f"✗ 预览失败: {response.status_code}")
        except Exception as e:
            print(f"✗ 请求失败: {e}")
        
        # 5. 查询推送记录
        print("\n5. 查询推送记录...")
        try:
            response = await client.get(
                f"{BASE_URL}/pushed-records",
                headers=headers,
                params={"limit": 5}
            )
            if response.status_code == 200:
                records = response.json()
                print(f"✓ 推送记录: {len(records)} 条")
                for r in records:
                    print(f"  - 内容ID:{r['content_id']} -> {r['target_id']} (状态: {r['push_status']})")
            else:
                print(f"✗ 查询推送记录失败: {response.status_code}")
        except Exception as e:
            print(f"✗ 请求失败: {e}")
        
        # 6. 更新规则（禁用）
        print(f"\n6. 禁用规则 ID={rule_id}...")
        try:
            response = await client.patch(
                f"{BASE_URL}/distribution-rules/{rule_id}",
                json={"enabled": False},
                headers=headers
            )
            if response.status_code == 200:
                updated_rule = response.json()
                print(f"✓ 规则已禁用: {updated_rule['name']}")
            else:
                print(f"✗ 更新规则失败: {response.status_code}")
        except Exception as e:
            print(f"✗ 请求失败: {e}")
        
        # 7. 删除测试规则
        print(f"\n7. 删除测试规则 ID={rule_id}...")
        try:
            response = await client.delete(
                f"{BASE_URL}/distribution-rules/{rule_id}",
                headers=headers
            )
            if response.status_code == 200:
                print("✓ 规则已删除")
            else:
                print(f"✗ 删除规则失败: {response.status_code}")
        except Exception as e:
            print(f"✗ 请求失败: {e}")
        
        print("\n" + "=" * 60)
        print("M4 功能测试完成")
        print("=" * 60)


if __name__ == "__main__":
    asyncio.run(test_m4_features())
