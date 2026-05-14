from pydantic import SecretStr

from app.core.config import settings, validate_settings


def test_validate_settings_rejects_empty_api_token_in_prod(monkeypatch):
    monkeypatch.setattr(settings, "app_env", "prod")
    monkeypatch.setattr(settings, "debug", False)
    monkeypatch.setattr(settings, "cors_allowed_origins", "https://vault.example.com")
    monkeypatch.setattr(settings, "api_token", SecretStr(""))

    try:
        validate_settings()
    except RuntimeError as exc:
        assert "API_TOKEN" in str(exc)
    else:
        raise AssertionError("validate_settings should reject empty API_TOKEN in production")


def test_validate_settings_allows_explicit_api_token_in_prod(monkeypatch):
    monkeypatch.setattr(settings, "app_env", "prod")
    monkeypatch.setattr(settings, "debug", False)
    monkeypatch.setattr(settings, "cors_allowed_origins", "https://vault.example.com")
    monkeypatch.setattr(settings, "api_token", SecretStr("prod-token"))

    validate_settings()
