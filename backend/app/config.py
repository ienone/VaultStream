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
    
    # 全局代理配置（用于Telegram、Twitter、YouTube等）
    http_proxy: Optional[str] = None
    https_proxy: Optional[str] = None
    
    # 应用配置
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    base_url: Optional[str] = None  # 外部访问的基础 URL，例如 https://vault.example.com
    debug: bool = True
    debug_sql: bool = False  # 是否输出详细的SQL语句日志（默认关闭）

    # API 鉴权（M1：简单 Token）
    api_token: SecretStr = SecretStr("")

    # 日志配置
    log_level: str = "INFO"
    log_format: Literal["json", "text"] = "json"
    
    # B站配置
    bilibili_sessdata: Optional[SecretStr] = None
    bilibili_bili_jct: Optional[SecretStr] = None
    bilibili_buvid3: Optional[SecretStr] = None

    # 小红书/知乎/微博 配置 (需要 Cookie)
    xiaohongshu_cookie: Optional[SecretStr] = None
    zhihu_cookie: Optional[SecretStr] = None
    weibo_cookie: Optional[SecretStr] = None

    # Twitter/X 配置
    # 现在使用 FxTwitter API，无需任何登录凭证或配置
    # FxTwitter 是第三方 Twitter 内容解析服务，无需认证即可获取推文数据

    # 存储后端（用于私有归档的派生资产：图片 webp、未来音视频转码等）
    storage_backend: Literal["local", "s3"] = "local"
    storage_public_base_url: Optional[str] = None  # 若配置，可将 key 映射为可访问 URL

    # LocalFS
    storage_local_root: str = "data/storage"

    # S3/MinIO
    storage_s3_endpoint: Optional[str] = None
    storage_s3_region: str = "us-east-1"
    storage_s3_bucket: Optional[str] = None
    storage_s3_access_key: Optional[SecretStr] = None
    storage_s3_secret_key: Optional[SecretStr] = None

    # S3/MinIO URL 渲染
    # - 如果配置了 storage_public_base_url，URL 格式为：{base}/{bucket}/{key}
    # - 如果 storage_s3_presign_urls 为 True，生成预签名的 GET URL（适用于私有bucket）
    storage_s3_presign_urls: bool = False
    storage_s3_presign_expires: int = 3600

    # 媒体处理开关
    enable_archive_media_processing: bool = False
    archive_image_webp_quality: int = 80
    archive_image_max_count: Optional[int] = None
    
    class Config:
        env_file = ".env"
        case_sensitive = False


settings = Settings()


def validate_settings() -> None:
    """基础环境校验（M0）。

    注意：不要在错误信息里输出敏感值。
    """
    # 校验数据库路径
    if not settings.sqlite_db_path:
        raise RuntimeError("缺少 SQLITE_DB_PATH 配置")

    if settings.app_env == "prod" and settings.debug:
        raise RuntimeError("生产环境下 DEBUG 必须为 False")

    if settings.enable_bot:
        if not settings.telegram_bot_token or not settings.telegram_bot_token.get_secret_value():
            raise RuntimeError("ENABLE_BOT 为 True，但缺少 TELEGRAM_BOT_TOKEN")
        if not settings.telegram_channel_id:
            raise RuntimeError("ENABLE_BOT 为 True，但缺少 TELEGRAM_CHANNEL_ID")