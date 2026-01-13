"""
功能描述：分发规则管理 API
包含：规则增删改查
调用方式：需要 API Token
"""
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, desc
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import DistributionRule
from app.schemas import DistributionRuleCreate, DistributionRuleUpdate, DistributionRuleResponse
from app.logging import logger
from app.dependencies import require_api_token

router = APIRouter()

@router.post("/distribution-rules", response_model=DistributionRuleResponse)
async def create_distribution_rule(
    rule: DistributionRuleCreate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """创建分发规则"""
    result = await db.execute(
        select(DistributionRule).where(DistributionRule.name == rule.name)
    )
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Rule name already exists")
    
    db_rule = DistributionRule(**rule.model_dump())
    db.add(db_rule)
    await db.commit()
    await db.refresh(db_rule)
    
    logger.info(f"分发规则已创建: {db_rule.name} (ID: {db_rule.id})")
    return db_rule

@router.get("/distribution-rules", response_model=List[DistributionRuleResponse])
async def list_distribution_rules(
    enabled: Optional[bool] = None,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取所有分发规则"""
    query = select(DistributionRule).order_by(desc(DistributionRule.priority), DistributionRule.id)
    if enabled is not None:
        query = query.where(DistributionRule.enabled == enabled)
    result = await db.execute(query)
    return result.scalars().all()

@router.get("/distribution-rules/{rule_id}", response_model=DistributionRuleResponse)
async def get_distribution_rule(
    rule_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取单个分发规则"""
    result = await db.execute(select(DistributionRule).where(DistributionRule.id == rule_id))
    rule = result.scalar_one_or_none()
    if not rule:
        raise HTTPException(status_code=404, detail="Distribution rule not found")
    return rule

@router.patch("/distribution-rules/{rule_id}", response_model=DistributionRuleResponse)
async def update_distribution_rule(
    rule_id: int,
    rule_update: DistributionRuleUpdate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """更新分发规则"""
    result = await db.execute(select(DistributionRule).where(DistributionRule.id == rule_id))
    db_rule = result.scalar_one_or_none()
    if not db_rule:
        raise HTTPException(status_code=404, detail="Distribution rule not found")
    
    update_data = rule_update.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(db_rule, key, value)
    
    await db.commit()
    await db.refresh(db_rule)
    logger.info(f"分发规则已更新: {db_rule.name} (ID: {db_rule.id})")
    return db_rule

@router.delete("/distribution-rules/{rule_id}")
async def delete_distribution_rule(
    rule_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """删除分发规则"""
    result = await db.execute(select(DistributionRule).where(DistributionRule.id == rule_id))
    db_rule = result.scalar_one_or_none()
    if not db_rule:
        raise HTTPException(status_code=404, detail="Distribution rule not found")
    
    await db.delete(db_rule)
    await db.commit()
    logger.info(f"分发规则已删除: {db_rule.name} (ID: {rule_id})")
    return {"status": "deleted", "id": rule_id}
