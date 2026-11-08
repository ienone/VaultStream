from __future__ import annotations

import random
from collections.abc import MutableMapping

import httpx


def exponential_backoff(
    attempt: int,
    *,
    base_seconds: float = 1.0,
    jitter_max: float = 1.0,
) -> float:
    """Compute exponential backoff with optional jitter."""
    wait = base_seconds * (2 ** max(0, attempt))
    if jitter_max > 0:
        wait += random.uniform(0.0, jitter_max)
    return wait


def merge_response_cookies(
    jar: MutableMapping[str, str],
    response: httpx.Response,
) -> int:
    """Merge response cookies into the provided jar and return update count."""
    changed = 0
    for name, value in response.cookies.items():
        if not value:
            continue
        if jar.get(name) != value:
            jar[name] = value
            changed += 1
    return changed
