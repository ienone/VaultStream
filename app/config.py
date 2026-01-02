"""
配置管理
"""
from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    """应用配置"""
    
    # 数据库配置
    database_url: str = "postgresql+asyncpg://user:password@localhost:5432/vaultstream"
    
    # Redis 配置
    redis_url: str = "redis://localhost:6379/0"
    
    # Telegram Bot 配置
    telegram_bot_token: str = ""
    telegram_channel_id: str = ""
    telegram_proxy_url: Optional[str] = None
    
    # 应用配置
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    debug: bool = True
    
    # B站配置
    bilibili_sessdata: Optional[str] = None
    bilibili_bili_jct: Optional[str] = None
    bilibili_buvid3: Optional[str] = None
    
    class Config:
        env_file = ".env"
        case_sensitive = False


settings = Settings()
