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

    # Bot 权限控制
    telegram_admin_ids: str = ""  # 管理员用户ID列表，逗号分隔，如 "123456,789012"
    telegram_whitelist_ids: str = ""  # 白名单用户ID列表，逗号分隔。为空则允许所有用户
    telegram_blacklist_ids: str = ""  # 黑名单用户ID列表，逗号分隔

    # Napcat/OneBot 11 配置
    enable_napcat: bool = False
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
    slow_query_threshold_ms: int = 500  # 慢查询日志阈值（毫秒），0 表示关闭

    # CORS 允许的来源（逗号分隔），"*" 表示全部允许（仅限开发环境）
    cors_allowed_origins: str = "*"

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

    # LLM 配置 (Text)
    text_llm_api_key: Optional[SecretStr] = None
    text_llm_base_url: Optional[str] = None
    text_llm_model: str = "deepseek-chat"

    # LLM 配置 (Vision)
    vision_llm_api_key: Optional[SecretStr] = None
    vision_llm_base_url: Optional[str] = None
    vision_llm_model: str = "qwen-vl-max"

    # 存储后端配置
    storage_backend: Literal["local", "s3"] = "local"
    storage_public_base_url: Optional[str] = None

    # LocalFS
    storage_local_root: str = "data/storage"

    # 分发队列系统
    queue_worker_count: int = 3  # 队列Worker并发数
    parse_worker_count: int = 1  # 解析任务Worker并发数

    # 事件总线
    enable_event_outbox_polling: bool = False  # 单实例部署时可关闭 outbox 轮询
    max_sse_subscribers: int = 100  # SSE 最大连接数上限

    # 摘要生成
    enable_auto_summary: bool = False

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

    if settings.app_env == "prod":
        token = settings.api_token.get_secret_value()
        if not token:
            raise RuntimeError("API_TOKEN must be set in production (APP_ENV=prod)")
        if settings.cors_allowed_origins == "*":
            raise RuntimeError("CORS_ALLOWED_ORIGINS must not be '*' in production")

    return None
