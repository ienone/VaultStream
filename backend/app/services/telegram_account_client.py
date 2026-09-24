"""Shared transport configuration for explicit login and account synchronization."""
import os
from pathlib import Path
from urllib.parse import unquote, urlsplit
from telethon import TelegramClient
from app.core.config import settings


def create_account_client(*, receive_updates=False):
    if not settings.telegram_api_id or not settings.telegram_api_hash.get_secret_value():
        raise ValueError("请先配置 Telegram 应用凭据")
    path = Path(settings.telegram_session_path)
    if path.suffix != ".session":
        path = Path(str(path) + ".session")
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_CREAT | os.O_WRONLY, 0o600)
    os.close(descriptor)
    path.chmod(0o600)
    proxy = None
    proxy_url = settings.https_proxy or settings.http_proxy
    if proxy_url:
        parts = urlsplit(proxy_url)
        proxy = {"proxy_type": parts.scheme, "addr": parts.hostname,
                 "port": parts.port or (1080 if parts.scheme.startswith("socks") else 80),
                 "username": unquote(parts.username) if parts.username else None,
                 "password": unquote(parts.password) if parts.password else None}
    return TelegramClient(str(path), settings.telegram_api_id,
                          settings.telegram_api_hash.get_secret_value(), proxy=proxy,
                          receive_updates=receive_updates, flood_sleep_threshold=0)
