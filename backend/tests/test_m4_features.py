"""
M4 功能测试脚本 (Pytest Refactored)
测试分发规则、审批流程和推送记录功能
"""
import pytest
from sqlalchemy import select, desc
from app.models import Content, ContentStatus, DistributionRule, ReviewStatus
from app.schemas import DistributionRuleCreate, ReviewAction

import random

@pytest.mark.asyncio
async def test_distribution_rules_crud(client, db_session):
    """测试分发规则的创建、查询和删除"""
    rule_name = f"TestRule-{random.randint(1000, 9999)}"
    
    # 1. Create
    payload = {
        "name": rule_name,
        "description": "Integration Test Rule",
        "match_conditions": {"tags": ["test"], "is_nsfw": False},
        "targets": [{"platform": "telegram", "target_id": "@test_channel", "enabled": True}],
        "enabled": True,
        "priority": 5,
        "nsfw_policy": "block",
        "approval_required": True
    }
    
    resp = await client.post("/api/v1/distribution-rules", json=payload)
    assert resp.status_code == 200, f"Create failed: {resp.text}"
    rule_id = resp.json()["id"]
    
    # 2. List
    resp = await client.get("/api/v1/distribution-rules")
    assert resp.status_code == 200
    rules = resp.json()
    assert any(r["id"] == rule_id for r in rules)
    
    # 3. Delete
    resp = await client.delete(f"/api/v1/distribution-rules/{rule_id}")
    assert resp.status_code == 200

@pytest.mark.asyncio
async def test_review_flow(client, db_session):
    """测试内容审批流程 (使用真实数据库中的内容)"""
    # 1. Find a content item to review
    # We look for ANY content, or create a dummy one if empty?
    # Requirement: "Query existing records"
    result = await db_session.execute(
        select(Content).limit(1)
    )
    content = result.scalar_one_or_none()
    
    if not content:
        pytest.skip("Database is empty, skipping review test")
    
    content_id = content.id
    original_status = content.review_status
    
    print(f"Testing review on Content ID: {content_id}")
    
    # 2. Submit Review (Approve)
    payload = {
        "action": "approve",
        "reviewed_by": "pytest_bot",
        "note": "Automated test approval"
    }
    resp = await client.post(f"/api/v1/contents/{content_id}/review", json=payload)
    assert resp.status_code == 200
    data = resp.json()
    assert data["review_status"] == ReviewStatus.APPROVED
    
    # 3. Verify in DB
    await db_session.refresh(content)
    assert content.review_status == ReviewStatus.APPROVED
    
    # Restore status (Optional, but good for "real data" hygiene)
    # content.review_status = original_status
    # await db_session.commit()

@pytest.mark.asyncio
async def test_bot_get_content(client, db_session):
    """测试机器人拉取内容接口"""
    # Find a content that is PULLED or DISTRIBUTED
    result = await db_session.execute(
        select(Content).where(
            Content.status.in_([ContentStatus.PULLED, ContentStatus.DISTRIBUTED])
        ).limit(1)
    )
    content = result.scalar_one_or_none()
    
    if not content:
        pytest.skip("No suitable content for bot pull test")
        
    payload = {
        "target_platform": "telegram",
        "limit": 5,
        "tag": None # Optional
    }
    
    resp = await client.post("/api/v1/bot/get-content", json=payload)
    assert resp.status_code == 200
    items = resp.json()
    assert isinstance(items, list)
    # Note: It might return empty list if all contents are already pushed to telegram
    # But the API call itself should succeed.