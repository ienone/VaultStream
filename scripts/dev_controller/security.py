from __future__ import annotations

import re


_QUERY_SECRET_RE = re.compile(
    r"(?i)(?P<key>(?:api[_-]?)?token|signature|authorization|secret|key)"
    r"=(?P<value>[^&\s]+)"
)
_BEARER_RE = re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+")
_HEADER_SECRET_RE = re.compile(
    r"(?im)^(?P<key>X-API-Token|Authorization|Cookie|Set-Cookie)\s*:\s*.+$"
)


def redact_text(value: str) -> str:
    """Remove common credentials from captured tool and Flutter output."""

    value = _QUERY_SECRET_RE.sub(
        lambda match: f"{match.group('key')}=<redacted>", value
    )
    value = _BEARER_RE.sub("Bearer <redacted>", value)
    return _HEADER_SECRET_RE.sub(
        lambda match: f"{match.group('key')}: <redacted>", value
    )
