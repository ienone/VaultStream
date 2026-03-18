from __future__ import annotations

import random
from collections.abc import MutableMapping

import httpx


def truncated_gaussian_delay(
    *,
    base_delay: float = 1.0,
    mean: float = 0.3,
    sigma: float = 0.15,
    long_pause_probability: float = 0.0,
    long_pause_range: tuple[float, float] = (2.0, 5.0),
) -> float:
    """Build a human-like request delay with optional long-tail pauses."""
    jitter = max(0.0, random.gauss(mean, sigma))
    if long_pause_probability > 0 and random.random() < long_pause_probability:
        jitter += random.uniform(*long_pause_range)
    return max(0.0, base_delay + jitter)


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


def progressive_captcha_cooldown(
    verify_count: int,
    *,
    first_wait_seconds: float = 5.0,
    max_wait_seconds: float = 30.0,
) -> float:
    """5->10->20->30 style cooldown used after captcha/risk triggers."""
    if verify_count <= 0:
        return 0.0
    return min(max_wait_seconds, first_wait_seconds * (2 ** (verify_count - 1)))


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
