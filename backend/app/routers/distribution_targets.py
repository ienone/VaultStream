"""
分发目标（DistributionTarget）CRUD API

提供规则关联分发目标的管理接口。
"""
from typing import List
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import require_api_token
from app.core.logging import logger
from app.distribution.queue_service import mark_historical_parse_success_as_pushed_for_rule
from app.models import DistributionTarget, DistributionRule, BotChat
from app.schemas import (
    DistributionTargetCreate,
    DistributionTargetUpdate,
    DistributionTargetResponse,
)

router = APIRouter(prefix="/distribution-rules", tags=["distribution-targets"])


@router.get("/{rule_id}/targets", response_model=List[DistributionTargetResponse])
async def list_rule_targets(
    rule_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取规则的所有分发目标"""
    # 验证规则存在
    rule_result = await db.execute(
        select(DistributionRule).where(DistributionRule.id == rule_id)
    )
    if not rule_result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Rule not found")
    
    # 查询目标
    result = await db.execute(
        select(DistributionTarget)
        .where(DistributionTarget.rule_id == rule_id)
        .order_by(DistributionTarget.created_at.asc())
    )
    targets = result.scalars().all()
    
    return [DistributionTargetResponse.model_validate(t) for t in targets]


@router.post("/{rule_id}/targets", response_model=DistributionTargetResponse, status_code=201)
async def create_rule_target(
    rule_id: int,
    target: DistributionTargetCreate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """为规则添加分发目标"""
    # 验证规则存在
    rule_result = await db.execute(
        select(DistributionRule).where(DistributionRule.id == rule_id)
    )
    rule = rule_result.scalar_one_or_none()
    if not rule:
        raise HTTPException(status_code=404, detail="Rule not found")
    
    # 验证 BotChat 存在
    chat_result = await db.execute(
        select(BotChat).where(BotChat.id == target.bot_chat_id)
    )
    chat = chat_result.scalar_one_or_none()
    if not chat:
        raise HTTPException(status_code=404, detail="BotChat not found")
    
    # 检查是否已存在（防止重复）
    existing = await db.execute(
        select(DistributionTarget).where(
            DistributionTarget.rule_id == rule_id,
            DistributionTarget.bot_chat_id == target.bot_chat_id
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=400,
            detail=f"Target already exists for rule '{rule.name}' and chat '{chat.chat_id}'"
        )
    
    # 创建目标
    db_target = DistributionTarget(
        rule_id=rule_id,
        bot_chat_id=target.bot_chat_id,
        enabled=target.enabled,
        merge_forward=target.merge_forward,
        use_author_name=target.use_author_name,
        summary=target.summary,
        render_config_override=target.render_config_override,
    )
    db.add(db_target)

    inserted = await mark_historical_parse_success_as_pushed_for_rule(
        session=db,
        rule_id=rule_id,
        bot_chat_id=target.bot_chat_id,
    )

    await db.commit()
    await db.refresh(db_target)
    
    logger.info(
        f"Created distribution target: rule={rule.name}, chat={chat.chat_id}, "
        f"enabled={db_target.enabled}, backfilled_success={inserted}"
    )
    
    return DistributionTargetResponse.model_validate(db_target)


@router.patch("/{rule_id}/targets/{target_id}", response_model=DistributionTargetResponse)
async def update_rule_target(
    rule_id: int,
    target_id: int,
    update: DistributionTargetUpdate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """更新分发目标配置"""
    # 查询目标
    result = await db.execute(
        select(DistributionTarget).where(
            DistributionTarget.id == target_id,
            DistributionTarget.rule_id == rule_id
        )
    )
    db_target = result.scalar_one_or_none()
    if not db_target:
        raise HTTPException(status_code=404, detail="Target not found")
    
    # 更新字段
    update_data = update.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(db_target, key, value)
    
    await db.commit()
    await db.refresh(db_target)
    
    logger.info(f"Updated distribution target: id={target_id}")
    
    return DistributionTargetResponse.model_validate(db_target)


@router.delete("/{rule_id}/targets/{target_id}", status_code=204)
async def delete_rule_target(
    rule_id: int,
    target_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """删除分发目标"""
    result = await db.execute(
        select(DistributionTarget).where(
            DistributionTarget.id == target_id,
            DistributionTarget.rule_id == rule_id
        )
    )
    db_target = result.scalar_one_or_none()
    if not db_target:
        raise HTTPException(status_code=404, detail="Target not found")
    
    await db.delete(db_target)
    await db.commit()
    
    logger.info(f"Deleted distribution target: id={target_id}")
