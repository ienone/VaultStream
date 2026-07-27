"""资源级媒体签名，不复用控制面 API Token。"""

import hashlib
import hmac
import secrets
import time
from dataclasses import dataclass
from urllib.parse import quote

from app.core.config import settings


_DEVELOPMENT_SECRET = secrets.token_bytes(32)


@dataclass(frozen=True)
class MediaSignatureError(Exception):
    code: str


def _signing_secret() -> bytes:
    configured = settings.media_signing_secret.get_secret_value()
    if configured:
        return configured.encode("utf-8")
    if settings.app_env == "prod":
        raise RuntimeError("MEDIA_SIGNING_SECRET is required in production")
    return _DEVELOPMENT_SECRET


def _signature_payload(storage_key: str, variant_id: int, expires: int) -> bytes:
    return f"v1\n{variant_id}\n{expires}\n{storage_key}".encode("utf-8")


def sign_media_key(storage_key: str, variant_id: int, expires: int) -> str:
    return hmac.new(
        _signing_secret(),
        _signature_payload(storage_key, variant_id, expires),
        hashlib.sha256,
    ).hexdigest()


def verify_media_signature(
    storage_key: str,
    variant_id: int,
    expires: int,
    signature: str,
    *,
    now: int | None = None,
) -> None:
    current_time = int(time.time()) if now is None else now
    if expires < current_time:
        raise MediaSignatureError("media_signature_expired")
    expected = sign_media_key(storage_key, variant_id, expires)
    if not hmac.compare_digest(expected, signature):
        raise MediaSignatureError("media_signature_invalid")


def build_signed_media_url(
    base_url: str,
    storage_key: str,
    variant_id: int,
    *,
    expires: int,
) -> str:
    encoded_key = quote(storage_key, safe="/")
    signature = sign_media_key(storage_key, variant_id, expires)
    return (
        f"{base_url.rstrip('/')}/api/v1/media/blobs/{encoded_key}"
        f"?variant_id={variant_id}&expires={expires}&signature={signature}"
    )
