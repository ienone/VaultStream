from __future__ import annotations

import re
from pathlib import Path


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


def resolve_test_target(frontend_dir: Path, raw_target: str) -> Path:
    """Resolve a test target while keeping it inside frontend/test."""

    if not isinstance(raw_target, str):
        raise ValueError("测试路径必须是字符串")
    if not raw_target or len(raw_target) > 300 or "\x00" in raw_target:
        raise ValueError("测试路径为空或过长")

    frontend_dir = frontend_dir.resolve()
    test_root = (frontend_dir / "test").resolve()
    candidate = (frontend_dir / raw_target).resolve()

    if test_root != candidate and test_root not in candidate.parents:
        raise ValueError("测试必须位于 frontend/test")
    if candidate.suffix != ".dart" or not candidate.name.endswith("_test.dart"):
        raise ValueError("只允许执行 *_test.dart")
    if not candidate.is_file():
        raise ValueError("测试文件不存在")
    return candidate
