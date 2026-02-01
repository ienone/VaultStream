"""
爬虫配置 API

提供爬虫延迟规则组的 CRUD 操作：
- 默认延迟配置
- 规则组管理（自定义名称、域名列表、延迟时间、优先级）
"""
from typing import List, Optional, Dict
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
import uuid

from app.core.dependencies import require_api_token
from app.services.settings_service import get_setting_value, set_setting_value
from app.core.crawler_config import (
    DEFAULT_DELAY,
    BUILTIN_RULE_GROUPS,
    SETTING_KEY_DEFAULT_DELAY,
    SETTING_KEY_RULE_GROUPS,
)

router = APIRouter()


# ========== Schemas ==========

class RuleGroupBase(BaseModel):
    """规则组基础字段"""
    name: str = Field(..., min_length=1, max_length=50, description="规则组名称")
    delay: float = Field(..., ge=0, le=120, description="延迟时间（秒）")
    domains: List[str] = Field(default_factory=list, description="域名列表")
    enabled: bool = Field(default=True, description="是否启用")
    priority: int = Field(default=0, ge=-100, le=100, description="优先级（越大越优先）")


class RuleGroupCreate(RuleGroupBase):
    """创建规则组请求"""
    pass


class RuleGroupUpdate(BaseModel):
    """更新规则组请求"""
    name: Optional[str] = Field(None, min_length=1, max_length=50)
    delay: Optional[float] = Field(None, ge=0, le=120)
    domains: Optional[List[str]] = None
    enabled: Optional[bool] = None
    priority: Optional[int] = Field(None, ge=-100, le=100)


class RuleGroupResponse(RuleGroupBase):
    """规则组响应"""
    id: str = Field(..., description="规则组ID")
    is_builtin: bool = Field(default=False, description="是否为内置规则组")


class RuleGroupListResponse(BaseModel):
    """规则组列表响应"""
    builtin: List[RuleGroupResponse] = Field(..., description="内置规则组（只读）")
    custom: List[RuleGroupResponse] = Field(..., description="用户自定义规则组")


class DefaultDelayResponse(BaseModel):
    """默认延迟响应"""
    default_delay: float


class DefaultDelayUpdate(BaseModel):
    """默认延迟更新"""
    default_delay: float = Field(..., ge=0, le=120)


class AddDomainsRequest(BaseModel):
    """添加域名请求"""
    domains: List[str] = Field(..., min_length=1, description="要添加的域名列表")


class RemoveDomainsRequest(BaseModel):
    """移除域名请求"""
    domains: List[str] = Field(..., min_length=1, description="要移除的域名列表")


# ========== Helper Functions ==========

def _builtin_to_response(group_id: str, group: dict) -> RuleGroupResponse:
    """将内置规则组转换为响应格式"""
    return RuleGroupResponse(
        id=group_id,
        name=group.get("name", group_id),
        delay=group.get("delay", DEFAULT_DELAY),
        domains=group.get("domains", []),
        enabled=group.get("enabled", True),
        priority=group.get("priority", 0),
        is_builtin=True,
    )


def _custom_to_response(group_id: str, group: dict) -> RuleGroupResponse:
    """将自定义规则组转换为响应格式"""
    return RuleGroupResponse(
        id=group_id,
        name=group.get("name", "未命名规则组"),
        delay=group.get("delay", DEFAULT_DELAY),
        domains=group.get("domains", []),
        enabled=group.get("enabled", True),
        priority=group.get("priority", 0),
        is_builtin=False,
    )


# ========== API Endpoints ==========

@router.get("/config/default-delay", response_model=DefaultDelayResponse)
async def get_default_delay(
    _: None = Depends(require_api_token),
):
    """获取默认延迟配置"""
    delay = await get_setting_value(SETTING_KEY_DEFAULT_DELAY, DEFAULT_DELAY)
    return DefaultDelayResponse(default_delay=float(delay))


@router.put("/config/default-delay", response_model=DefaultDelayResponse)
async def update_default_delay(
    update: DefaultDelayUpdate,
    _: None = Depends(require_api_token),
):
    """更新默认延迟配置"""
    await set_setting_value(
        SETTING_KEY_DEFAULT_DELAY,
        update.default_delay,
        category="crawler",
        description="默认页面加载等待时间（秒）"
    )
    return DefaultDelayResponse(default_delay=update.default_delay)


@router.get("/config/rule-groups", response_model=RuleGroupListResponse)
async def list_rule_groups(
    _: None = Depends(require_api_token),
):
    """获取所有规则组"""
    # 内置规则组
    builtin = [
        _builtin_to_response(gid, group)
        for gid, group in BUILTIN_RULE_GROUPS.items()
    ]
    
    # 用户自定义规则组
    custom_groups = await get_setting_value(SETTING_KEY_RULE_GROUPS, {})
    custom = []
    if isinstance(custom_groups, dict):
        custom = [
            _custom_to_response(gid, group)
            for gid, group in custom_groups.items()
        ]
    
    return RuleGroupListResponse(builtin=builtin, custom=custom)


@router.get("/config/rule-groups/{group_id}", response_model=RuleGroupResponse)
async def get_rule_group(
    group_id: str,
    _: None = Depends(require_api_token),
):
    """获取单个规则组"""
    # 检查内置规则组
    if group_id in BUILTIN_RULE_GROUPS:
        return _builtin_to_response(group_id, BUILTIN_RULE_GROUPS[group_id])
    
    # 检查自定义规则组
    custom_groups = await get_setting_value(SETTING_KEY_RULE_GROUPS, {})
    if isinstance(custom_groups, dict) and group_id in custom_groups:
        return _custom_to_response(group_id, custom_groups[group_id])
    
    raise HTTPException(status_code=404, detail=f"规则组不存在: {group_id}")


@router.post("/config/rule-groups", response_model=RuleGroupResponse)
async def create_rule_group(
    data: RuleGroupCreate,
    _: None = Depends(require_api_token),
):
    """创建自定义规则组"""
    custom_groups = await get_setting_value(SETTING_KEY_RULE_GROUPS, {})
    if not isinstance(custom_groups, dict):
        custom_groups = {}
    
    # 生成唯一ID
    group_id = f"custom_{uuid.uuid4().hex[:8]}"
    
    # 清理域名
    domains = [d.lower().strip() for d in data.domains if d.strip()]
    
    custom_groups[group_id] = {
        "name": data.name,
        "delay": data.delay,
        "domains": domains,
        "enabled": data.enabled,
        "priority": data.priority,
    }
    
    await set_setting_value(
        SETTING_KEY_RULE_GROUPS,
        custom_groups,
        category="crawler",
        description="用户自定义爬虫规则组"
    )
    
    return _custom_to_response(group_id, custom_groups[group_id])


@router.put("/config/rule-groups/{group_id}", response_model=RuleGroupResponse)
async def update_rule_group(
    group_id: str,
    data: RuleGroupUpdate,
    _: None = Depends(require_api_token),
):
    """更新规则组"""
    # 不允许修改内置规则组
    if group_id in BUILTIN_RULE_GROUPS:
        raise HTTPException(status_code=403, detail="不能修改内置规则组")
    
    custom_groups = await get_setting_value(SETTING_KEY_RULE_GROUPS, {})
    if not isinstance(custom_groups, dict) or group_id not in custom_groups:
        raise HTTPException(status_code=404, detail=f"规则组不存在: {group_id}")
    
    group = custom_groups[group_id]
    
    # 更新字段
    if data.name is not None:
        group["name"] = data.name
    if data.delay is not None:
        group["delay"] = data.delay
    if data.domains is not None:
        group["domains"] = [d.lower().strip() for d in data.domains if d.strip()]
    if data.enabled is not None:
        group["enabled"] = data.enabled
    if data.priority is not None:
        group["priority"] = data.priority
    
    await set_setting_value(
        SETTING_KEY_RULE_GROUPS,
        custom_groups,
        category="crawler",
        description="用户自定义爬虫规则组"
    )
    
    return _custom_to_response(group_id, group)


@router.delete("/config/rule-groups/{group_id}")
async def delete_rule_group(
    group_id: str,
    _: None = Depends(require_api_token),
):
    """删除规则组"""
    # 不允许删除内置规则组
    if group_id in BUILTIN_RULE_GROUPS:
        raise HTTPException(status_code=403, detail="不能删除内置规则组")
    
    custom_groups = await get_setting_value(SETTING_KEY_RULE_GROUPS, {})
    if not isinstance(custom_groups, dict) or group_id not in custom_groups:
        raise HTTPException(status_code=404, detail=f"规则组不存在: {group_id}")
    
    del custom_groups[group_id]
    
    await set_setting_value(
        SETTING_KEY_RULE_GROUPS,
        custom_groups,
        category="crawler",
        description="用户自定义爬虫规则组"
    )
    
    return {"status": "deleted", "group_id": group_id}


@router.post("/config/rule-groups/{group_id}/domains")
async def add_domains_to_group(
    group_id: str,
    request: AddDomainsRequest,
    _: None = Depends(require_api_token),
):
    """向规则组添加域名"""
    if group_id in BUILTIN_RULE_GROUPS:
        raise HTTPException(status_code=403, detail="不能修改内置规则组")
    
    custom_groups = await get_setting_value(SETTING_KEY_RULE_GROUPS, {})
    if not isinstance(custom_groups, dict) or group_id not in custom_groups:
        raise HTTPException(status_code=404, detail=f"规则组不存在: {group_id}")
    
    group = custom_groups[group_id]
    current_domains = set(group.get("domains", []))
    
    added = []
    for domain in request.domains:
        domain = domain.lower().strip()
        if domain and domain not in current_domains:
            current_domains.add(domain)
            added.append(domain)
    
    group["domains"] = list(current_domains)
    
    await set_setting_value(
        SETTING_KEY_RULE_GROUPS,
        custom_groups,
        category="crawler",
        description="用户自定义爬虫规则组"
    )
    
    return {"status": "ok", "added": added, "total": len(group["domains"])}


@router.delete("/config/rule-groups/{group_id}/domains")
async def remove_domains_from_group(
    group_id: str,
    request: RemoveDomainsRequest,
    _: None = Depends(require_api_token),
):
    """从规则组移除域名"""
    if group_id in BUILTIN_RULE_GROUPS:
        raise HTTPException(status_code=403, detail="不能修改内置规则组")
    
    custom_groups = await get_setting_value(SETTING_KEY_RULE_GROUPS, {})
    if not isinstance(custom_groups, dict) or group_id not in custom_groups:
        raise HTTPException(status_code=404, detail=f"规则组不存在: {group_id}")
    
    group = custom_groups[group_id]
    current_domains = set(group.get("domains", []))
    
    removed = []
    for domain in request.domains:
        domain = domain.lower().strip()
        if domain in current_domains:
            current_domains.remove(domain)
            removed.append(domain)
    
    group["domains"] = list(current_domains)
    
    await set_setting_value(
        SETTING_KEY_RULE_GROUPS,
        custom_groups,
        category="crawler",
        description="用户自定义爬虫规则组"
    )
    
    return {"status": "ok", "removed": removed, "total": len(group["domains"])}


@router.get("/config/test-delay")
async def test_delay_for_url(
    url: str = Query(..., description="要测试的 URL"),
    _: None = Depends(require_api_token),
):
    """测试某个 URL 会使用的延迟时间"""
    from app.core.crawler_config import get_delay_for_url, extract_domain, find_matching_rule
    
    domain = extract_domain(url)
    group_id, group, delay = await find_matching_rule(domain)
    
    return {
        "url": url,
        "domain": domain,
        "delay": delay,
        "matched_rule": {
            "id": group_id,
            "name": group.get("name") if group else None,
            "is_builtin": group_id in BUILTIN_RULE_GROUPS if group_id else None,
        } if group_id else None,
    }
