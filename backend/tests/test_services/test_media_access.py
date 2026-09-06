import time
import pytest
from pydantic import SecretStr
from app.core.config import settings
from app.services.media_access import MediaSignatureError, sign_media_key, verify_media_signature


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
