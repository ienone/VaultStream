from __future__ import annotations

import httpx

from app.adapters.utils.anti_risk import (
    exponential_backoff,
    merge_response_cookies,
    progressive_captcha_cooldown,
    truncated_gaussian_delay,
)


def test_truncated_gaussian_delay_never_below_base():
    for _ in range(20):
        assert truncated_gaussian_delay(base_delay=1.0) >= 1.0


def test_exponential_backoff_without_jitter():
    assert exponential_backoff(0, jitter_max=0.0) == 1.0
    assert exponential_backoff(1, jitter_max=0.0) == 2.0
    assert exponential_backoff(2, jitter_max=0.0) == 4.0


def test_progressive_captcha_cooldown():
    assert progressive_captcha_cooldown(0) == 0.0
    assert progressive_captcha_cooldown(1) == 5.0
    assert progressive_captcha_cooldown(2) == 10.0
    assert progressive_captcha_cooldown(3) == 20.0
    assert progressive_captcha_cooldown(4) == 30.0
    assert progressive_captcha_cooldown(10) == 30.0


def test_merge_response_cookies_updates_jar():
    jar = {"a1": "old", "other": "x"}
    req = httpx.Request("GET", "https://example.com")
    resp = httpx.Response(
        200,
        headers=[
            ("set-cookie", "a1=new; Path=/; HttpOnly"),
            ("set-cookie", "web_session=abc; Path=/"),
        ],
        request=req,
    )

    changed = merge_response_cookies(jar, resp)

    assert changed == 2
    assert jar["a1"] == "new"
    assert jar["web_session"] == "abc"
