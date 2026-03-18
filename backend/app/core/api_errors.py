from __future__ import annotations

from typing import Any


def build_error_payload(
    *,
    message: str,
    code: str,
    hint: str | None = None,
    request_id: str | None = None,
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "detail": message,
        "error_message": message,
        "error_code": code,
        "error_hint": hint,
        "request_id": request_id,
    }
    if extra:
        payload.update(extra)
    return payload


def normalize_http_error_detail(detail: Any, *, status_code: int) -> dict[str, Any]:
    if isinstance(detail, dict):
        payload = dict(detail)
        message = str(payload.get("detail") or payload.get("error_message") or "Request failed")
    else:
        message = str(detail)
        payload = {"detail": message}

    payload.setdefault("detail", message)
    payload.setdefault("error_message", message)
    payload.setdefault("error_code", f"http_{status_code}")
    payload.setdefault("error_hint", None)
    payload.setdefault("request_id", None)
    return payload

