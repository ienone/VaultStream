import time

import pytest
from pydantic import SecretStr

from app.core.config import settings
from app.services.media_access import (
    MediaSignatureError,
    build_signed_media_url,
    sign_media_key,
    verify_media_signature,
)


def test_media_signature_binds_key_variant_and_expiry(monkeypatch):
    monkeypatch.setattr(settings, "media_signing_secret", SecretStr("media-secret"))
    expires = int(time.time()) + 60
    signature = sign_media_key("images/a.webp", 42, expires)

    verify_media_signature("images/a.webp", 42, expires, signature)

    with pytest.raises(MediaSignatureError) as changed_key:
        verify_media_signature("images/b.webp", 42, expires, signature)
    assert changed_key.value.code == "media_signature_invalid"

    with pytest.raises(MediaSignatureError) as changed_variant:
        verify_media_signature("images/a.webp", 43, expires, signature)
    assert changed_variant.value.code == "media_signature_invalid"


def test_expired_media_signature_has_stable_error_code(monkeypatch):
    monkeypatch.setattr(settings, "media_signing_secret", SecretStr("media-secret"))
    signature = sign_media_key("audio/a.m4a", 7, 99)

    with pytest.raises(MediaSignatureError) as expired:
        verify_media_signature("audio/a.m4a", 7, 99, signature, now=100)

    assert expired.value.code == "media_signature_expired"


def test_signed_url_does_not_contain_control_api_token(monkeypatch):
    monkeypatch.setattr(settings, "api_token", SecretStr("control-token"))
    monkeypatch.setattr(settings, "media_signing_secret", SecretStr("media-secret"))

    url = build_signed_media_url(
        "http://localhost:8000",
        "images/封面 a.webp",
        8,
        expires=1234567890,
    )

    assert "control-token" not in url
    assert "X-API-Token" not in url
    assert "/api/v1/media/blobs/images/" in url
    assert "variant_id=8" in url
