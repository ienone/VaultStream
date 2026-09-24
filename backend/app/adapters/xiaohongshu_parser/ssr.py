"""Read the public web state without executing page JavaScript."""
import json
import re

from bs4 import BeautifulSoup

from app.adapters.errors import NonRetryableAdapterError


def navigation_headers(headers: dict) -> dict:
    return {
        "User-Agent": headers["User-Agent"],
        "Accept": "text/html,application/xhtml+xml",
        "Upgrade-Insecure-Requests": "1",
        **{key: headers[key] for key in (
            "sec-ch-ua", "sec-ch-ua-mobile", "sec-ch-ua-platform",
        ) if key in headers},
    }


def extract_initial_state(html: str) -> dict:
    for script in BeautifulSoup(html, "html.parser").find_all("script"):
        text = script.string or ""
        match = re.search(r"\bwindow\.__INITIAL_STATE__\s*=\s*", text)
        if not match:
            continue
        # These two literals occur in the actual SSR state. Preserve strings,
        # including user text containing 'undefined' or 'new Set([])'.
        raw = re.sub(
            r'"(?:\\.|[^"\\])*"|new Set\(\[\]\)|\bundefined\b',
            lambda token: {"undefined": "null", "new Set([])": "[]"}.get(
                token.group(), token.group()
            ),
            text[match.end():],
        )
        try:
            data, _ = json.JSONDecoder().raw_decode(raw)
            if isinstance(data, dict):
                return data
        except ValueError:
            pass
        raise NonRetryableAdapterError("小红书 SSR 状态格式无效")
    raise NonRetryableAdapterError("小红书页面未提供详情状态")
