"""
Configuration management.
"""
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import SecretStr
from typing import Optional, Literal


class Settings(BaseSettings):
    """Application settings."""
    model_config = SettingsConfigDict(
        env_file=".env",
        case_sensitive=False,
        extra="ignore",
    )

    # 运行环境
    app_env: Literal["dev", "prod"] = "dev"

    # 数据库配置（仅支持 SQLite）
    database_type: Literal["sqlite"] = "sqlite"
    sqlite_db_path: str = "./data/vaultstream.db"

    # 队列配置（仅支持 SQLite 任务表）
    queue_type: Literal["sqlite"] = "sqlite"

    # Telegram Bot 配置
    enable_bot: bool = False
    telegram_bot_token: SecretStr = SecretStr("")
    telegram_channel_id: str = ""

    # Bot 权限控制
    telegram_admin_ids: str = ""  # 管理员用户ID列表，逗号分隔，如 "123456,789012"
    telegram_whitelist_ids: str = ""  # 白名单用户ID列表，逗号分隔。为空则允许所有用户
    telegram_blacklist_ids: str = ""  # 黑名单用户ID列表，逗号分隔

    # Napcat/OneBot 11 配置
    napcat_api_base: str = ""
    napcat_access_token: Optional[SecretStr] = None
    napcat_bot_uin: str = ""

    # 全局代理配置
    http_proxy: Optional[str] = None
    https_proxy: Optional[str] = None

    # 应用配置
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    base_url: Optional[str] = None  # 外部访问的基础 URL，例如 https://vault.example.com
    debug: bool = True
    debug_sql: bool = False

    # API 鉴权（简单 Token）
    api_token: SecretStr = SecretStr("")

    # 日志配置
    log_level: str = "INFO"
    log_format: Literal["json", "text"] = "json"

    # B站配置
    bilibili_sessdata: Optional[SecretStr] = None
    bilibili_bili_jct: Optional[SecretStr] = None
    bilibili_buvid3: Optional[SecretStr] = None

    # 小红书/知乎/微博 配置
    xiaohongshu_cookie: Optional[SecretStr] = None
    zhihu_cookie: Optional[SecretStr] = None
    weibo_cookie: Optional[SecretStr] = None

    # Twitter/X 配置
    # FxTwitter API 无需凭证

    # 存储后端配置
    storage_backend: Literal["local", "s3"] = "local"
    storage_public_base_url: Optional[str] = None

    # LocalFS
    storage_local_root: str = "data/storage"

    # S3/MinIO
    storage_s3_endpoint: Optional[str] = None
    storage_s3_region: str = "us-east-1"
    storage_s3_bucket: Optional[str] = None
    storage_s3_access_key: Optional[SecretStr] = None
    storage_s3_secret_key: Optional[SecretStr] = None

    # S3/MinIO URL 渲染
    storage_s3_presign_urls: bool = False
    storage_s3_presign_expires: int = 3600

    # 媒体处理
    enable_archive_media_processing: bool = True
    archive_image_webp_quality: int = 80
    archive_image_max_count: Optional[int] = None


settings = Settings()


def validate_settings() -> None:
    """基础环境校验"""
    if not settings.sqlite_db_path:
        raise RuntimeError("Missing SQLITE_DB_PATH")

    if settings.app_env == "prod" and settings.debug:
        raise RuntimeError("DEBUG must be False in production")

    if settings.enable_bot:
        if not settings.telegram_bot_token or not settings.telegram_bot_token.get_secret_value():
            raise RuntimeError("ENABLE_BOT is True but TELEGRAM_BOT_TOKEN is missing")
        if not settings.telegram_channel_id:
            raise RuntimeError("ENABLE_BOT is True but TELEGRAM_CHANNEL_ID is missing")
