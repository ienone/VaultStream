"""
配置管理
"""
from pydantic_settings import BaseSettings
from pydantic import SecretStr
from typing import Optional, Literal


class Settings(BaseSettings):
    """应用配置"""

    # 运行环境
    app_env: Literal["dev", "prod"] = "dev"
    
    # 数据库配置
    database_url: str = "postgresql+asyncpg://user:password@localhost:5432/vaultstream"
    
    # Redis 配置
    redis_url: str = "redis://localhost:6379/0"
    
    # Telegram Bot 配置
    enable_bot: bool = False
    telegram_bot_token: SecretStr = SecretStr("")
    telegram_channel_id: str = ""
    telegram_proxy_url: Optional[str] = None
    
    # 应用配置
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    debug: bool = True

    # 日志配置
    log_level: str = "INFO"
    log_format: Literal["json", "text"] = "json"
    
    # B站配置
    bilibili_sessdata: Optional[SecretStr] = None
    bilibili_bili_jct: Optional[SecretStr] = None
    bilibili_buvid3: Optional[SecretStr] = None
    
    class Config:
        env_file = ".env"
        case_sensitive = False


settings = Settings()


def validate_settings() -> None:
    """基础环境校验（M0）。

    注意：不要在错误信息里输出敏感值。
    """
    if not settings.database_url:
        raise RuntimeError("Missing DATABASE_URL")
    if not settings.redis_url:
        raise RuntimeError("Missing REDIS_URL")

    if settings.app_env == "prod" and settings.debug:
        raise RuntimeError("DEBUG must be False in prod")

    if settings.enable_bot:
        if not settings.telegram_bot_token or not settings.telegram_bot_token.get_secret_value():
            raise RuntimeError("ENABLE_BOT is True but TELEGRAM_BOT_TOKEN is missing")
        if not settings.telegram_channel_id:
            raise RuntimeError("ENABLE_BOT is True but TELEGRAM_CHANNEL_ID is missing")
