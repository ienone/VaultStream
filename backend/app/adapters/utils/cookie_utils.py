from __future__ import annotations

from typing import Optional


def strip_cookie_wrapper_quotes(raw_cookie: Optional[str]) -> str:
    """Strip one pair of wrapper quotes from a cookie string."""
    text = (raw_cookie or "").strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in ("'", '"'):
        return text[1:-1].strip()
    return text


def normalize_cookie_header_value(
    raw_cookie: Optional[str],
    *,
    ensure_outer_quotes: bool = False,
) -> str:
    """
    Normalize cookie header value text.

    - Always strips wrapper quotes first.
    - Optionally re-wraps with double quotes for endpoints sensitive to shape.
    """
    normalized = strip_cookie_wrapper_quotes(raw_cookie)
    if not normalized:
        return ""
    if ensure_outer_quotes:
        return f'"{normalized}"'
    return normalized
