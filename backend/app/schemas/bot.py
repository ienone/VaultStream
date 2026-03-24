"""
机器人相关的 schemas 
"""
from datetime import datetime
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field, ConfigDict

from app.models.bot import BotChatType, BotConfigPlatform
from app.schemas.base import UtcDatetime, OptionalUtcDatetime
from app.schemas.common import QueueStats, DistributionStatusStats


class TargetTestRequest(BaseModel):
    """
    Request payload for testing a target connection or bot connection
    """
    platform: str # telegram or qq
    target_id: Optional[str] = None
    bot_token: Optional[str] = None
    napcat_http_url: Optional[str] = None
    napcat_access_token: Optional[str] = None
    chat_id: Optional[str] = None


class BotChatCreate(BaseModel):
    bot_config_id: int
    chat_id: str
    chat_type: BotChatType
    title: Optional[str] = None
    username: Optional[str] = None
    description: Optional[str] = None
    enabled: bool = True
    is_monitoring: bool = False
    is_push_target: bool = False
    nsfw_chat_id: Optional[str] = None


class BotChatUpdate(BaseModel):
    chat_id: Optional[str] = None
    title: Optional[str] = None
    username: Optional[str] = None
    description: Optional[str] = None
    enabled: Optional[bool] = None
    is_monitoring: Optional[bool] = None
    is_push_target: Optional[bool] = None
    nsfw_chat_id: Optional[str] = None


class BotChatResponse(BaseModel):
    id: int
    bot_config_id: int
    chat_id: str
    chat_type: BotChatType
    title: Optional[str]
    username: Optional[str]
    description: Optional[str]
    
    member_count: Optional[int]
    is_admin: bool
    can_post: bool
    enabled: bool
    is_monitoring: bool
    is_push_target: bool
    
    nsfw_chat_id: Optional[str]
    
    total_pushed: int
    last_pushed_at: OptionalUtcDatetime
    
    is_accessible: bool
    last_sync_at: OptionalUtcDatetime
    sync_error: Optional[str]
    
    created_at: UtcDatetime
    updated_at: UtcDatetime
    
    model_config = ConfigDict(from_attributes=True)


class BotConfigCreate(BaseModel):
    platform: BotConfigPlatform
    name: str
    bot_token: Optional[str] = None
    napcat_http_url: Optional[str] = None
    napcat_ws_url: Optional[str] = None
    napcat_access_token: Optional[str] = None
    enabled: bool = True


class BotConfigUpdate(BaseModel):
    name: Optional[str] = None
    bot_token: Optional[str] = None
    napcat_http_url: Optional[str] = None
    napcat_ws_url: Optional[str] = None
    napcat_access_token: Optional[str] = None
    enabled: Optional[bool] = None


class BotConfigResponse(BaseModel):
    id: int
    platform: BotConfigPlatform
    name: str

    # 仅返回脱敏后的凭证文本，避免明文泄露。
    bot_token_masked: Optional[str] = None
    napcat_http_url: Optional[str] = None
    napcat_ws_url: Optional[str] = None
    napcat_access_token_masked: Optional[str] = None
    
    enabled: bool
    
    bot_id: Optional[str]
    bot_username: Optional[str]
    chat_count: int = 0
    
    created_at: UtcDatetime
    updated_at: UtcDatetime
    
    model_config = ConfigDict(from_attributes=True)


class BotRuntimeResponse(BaseModel):
    platform: Optional[BotConfigPlatform] = None
    bot_id: Optional[str]
    bot_username: Optional[str]
    bot_first_name: Optional[str]
    started_at: OptionalUtcDatetime
    last_heartbeat_at: OptionalUtcDatetime
    is_running: bool = False
    uptime_seconds: Optional[int] = None
    version: Optional[str]
    last_error: Optional[str]
    last_error_at: OptionalUtcDatetime
    updated_at: OptionalUtcDatetime = None
    
    model_config = ConfigDict(from_attributes=True)


class TelegramChatSyncResponse(BaseModel):
    """Telegram 聊天同步结果"""
    total: int
    added: int
    updated: int
    removed: int
    failed: int
    errors: List[str]


class BotStatusResponse(BaseModel):
    """Bot 状态响应"""
    is_running: bool
    bot_username: Optional[str] = None
    bot_id: Optional[int] = None
    connected_chats: int = 0
    total_pushed_today: int = 0
    uptime_seconds: Optional[int] = None
    napcat_status: Optional[str] = None

    parse_stats: QueueStats
    distribution_stats: DistributionStatusStats
    rule_breakdown: Dict[str, DistributionStatusStats] = Field(default_factory=dict)


class BotSyncRequest(BaseModel):
    """同步 Bot 聊天请求"""
    chat_id: Optional[str] = Field(None, description="指定同步的 Chat ID，为空则同步所有")


class BotChatUpsert(BaseModel):
    """Bot 聊天 Upsert（用于 Bot 进程上报）"""
    bot_config_id: int = Field(..., ge=1, description="所属 BotConfig ID")
    chat_id: str = Field(..., description="Telegram Chat ID")
    chat_type: str = Field(..., description="channel/group/supergroup/private")
    title: Optional[str] = None
    username: Optional[str] = None
    description: Optional[str] = None
    member_count: Optional[int] = None
    is_admin: bool = False
    can_post: bool = False
    raw_data: Optional[Dict] = None


class BotHeartbeat(BaseModel):
    """Bot 心跳请求"""
    platform: BotConfigPlatform = BotConfigPlatform.TELEGRAM
    bot_id: str
    bot_username: str
    bot_first_name: Optional[str] = None
    version: str = "0.1.0"
    error: Optional[str] = None


class BotSyncResult(BaseModel):
    """Bot 群组同步结果"""
    total: int
    updated: int
    failed: int
    inaccessible: int
    details: List[Dict] = Field(default_factory=list)


class ChatRuleBindingInfo(BaseModel):
    """群组已绑定规则信息"""
    rule_id: int
    name: str
    enabled: bool = True


class BotChatRulesResponse(BaseModel):
    """群组规则列表"""
    bot_chat_id: int
    chat_id: str
    rule_ids: List[int] = Field(default_factory=list)
    rules: List[ChatRuleBindingInfo] = Field(default_factory=list)


class BotChatRuleAssignRequest(BaseModel):
    """群组规则绑定更新请求"""
    rule_ids: List[int] = Field(default_factory=list)


class BotConfigBase(BaseModel):
    """Bot 配置基础字段"""
    platform: str = Field(..., pattern=r"^(telegram|qq)$")
    name: str = Field(..., min_length=1, max_length=100)
    bot_token: Optional[str] = None
    napcat_http_url: Optional[str] = None
    napcat_ws_url: Optional[str] = None
    napcat_access_token: Optional[str] = None
    enabled: bool = True


class BotConfigSyncChatsResponse(BaseModel):
    """Bot 配置同步群组响应"""
    bot_config_id: int
    total: int = 0
    updated: int = 0
    created: int = 0
    failed: int = 0
    details: List[Dict[str, Any]] = Field(default_factory=list)


class BotConfigQrCodeResponse(BaseModel):
    """Napcat 登录二维码响应"""
    bot_config_id: int
    status: str
    qr_code: Optional[str] = None
    message: Optional[str] = None


class TargetTestResponse(BaseModel):
    """测试目标连接响应"""
    status: str = Field(..., description="ok or error")
    message: Optional[str] = None
    details: Optional[Dict[str, Any]] = Field(None, description="详细错误信息")
