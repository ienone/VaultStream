"""Identify specific parser capabilities without falling back to universal."""

from dataclasses import dataclass
import re
from urllib.parse import urlsplit, urlunsplit

import httpx

from app.core.safe_fetch import create_safe_async_transport, safe_client_get


@dataclass(frozen=True)
class ParseCapability:
    url: str
    platform: str | None = None
    content_type: str | None = None
    short_link: bool = False
    reason: str = "unsupported_url"

    @property
    def supported(self) -> bool:
        return self.platform is not None and self.content_type is not None


def dedicated_parse_capability(url: str) -> ParseCapability:
    """Recognize actual objects, rather than platform names in arbitrary URLs."""
    try:
        parsed = urlsplit(url.strip())
        host = (parsed.hostname or "").lower()
        if (parsed.scheme not in {"http", "https"} or not host
                or parsed.username is not None or parsed.password is not None
                or parsed.port not in {None, 80, 443}
                or any(char in url for char in "\\\r\n\t")):
            return ParseCapability(url)
    except ValueError:
        return ParseCapability(url)

    path = parsed.path.rstrip("/")
    normalized = urlunsplit(("https", host, path, parsed.query, ""))
    if host == "b23.tv" or host.endswith(".b23.tv") or host == "bilibili.com" or host.endswith(".bilibili.com"):
        return ParseCapability(normalized, reason="excluded_platform")

    def supported(platform: str, content_type: str, canonical: str | None = None):
        return ParseCapability(canonical or normalized, platform, content_type, reason="supported")

    if host in {"xhslink.com", "www.xhslink.com"} and re.fullmatch(r"/(?:a/|o/)?[A-Za-z0-9]+", path):
        return ParseCapability(normalized, "xiaohongshu", short_link=True, reason="short_link")
    if host == "mapp.api.weibo.cn" and re.fullmatch(r"/fx/[A-Za-z0-9]+(?:\.html)?", path):
        return ParseCapability(normalized, "weibo", short_link=True, reason="short_link")

    if host in {"xiaohongshu.com", "www.xiaohongshu.com"}:
        if re.fullmatch(r"/(?:explore|discovery/item)/[a-f0-9]{24}", path):
            return supported("xiaohongshu", "note")
        if re.fullmatch(r"/user/profile/[a-f0-9]{24}", path):
            return supported("xiaohongshu", "user_profile")

    if host in {"weibo.com", "www.weibo.com", "weibo.cn", "m.weibo.cn"}:
        match = re.fullmatch(r"/(?:detail|2/detail|status|\d+)/([A-Za-z0-9]+)", path)
        if match:
            return supported("weibo", "status", f"https://weibo.com/detail/{match[1]}")
        if re.fullmatch(r"/u/\d+", path):
            return supported("weibo", "user", f"https://weibo.com{path}")

    if host in {"twitter.com", "www.twitter.com", "mobile.twitter.com", "x.com", "www.x.com", "mobile.x.com"}:
        match = re.fullmatch(r"/([A-Za-z0-9_]{1,15})/status/([0-9]+)(?:/(?:photo|video)/[0-9]+)?", path)
        if match:
            return supported("twitter", "tweet", f"https://x.com/{match[1]}/status/{match[2]}")

    if host in {"zhihu.com", "www.zhihu.com"}:
        patterns = {
            "answer": r"/(?:question/\d+/)?answer/\d+",
            "question": r"/question/\d+",
            "pin": r"/pin/\d+",
            "user_profile": r"/people/[A-Za-z0-9_-]+",
            "column": r"/column/[A-Za-z0-9_-]+",
            "collection": r"/collection/\d+",
        }
        for content_type, pattern in patterns.items():
            if re.fullmatch(pattern, path):
                return supported("zhihu", content_type, f"https://www.zhihu.com{path}")
    if host == "zhuanlan.zhihu.com":
        if re.fullmatch(r"/p/\d+", path):
            return supported("zhihu", "article", f"https://{host}{path}")
        if re.fullmatch(r"/[A-Za-z0-9_][A-Za-z0-9_-]+", path):
            return supported("zhihu", "column", f"https://{host}{path}")

    if host == "t.me":
        match = re.fullmatch(r"/(?:s/)?([A-Za-z][A-Za-z0-9_]{0,63})/([0-9]+)", path)
        if match and match[1].lower() not in {"c", "s", "share", "joinchat", "addstickers"}:
            return supported("telegram", "post", f"https://t.me/{match[1]}/{match[2]}")

    # RSS parse() returns the latest feed entry, not the object shared by the
    # user. Feed URLs must not silently become unrelated article previews.
    return ParseCapability(normalized)


async def resolve_dedicated_parse_capability(url: str) -> ParseCapability:
    capability = dedicated_parse_capability(url)
    if not capability.short_link:
        return capability
    async with httpx.AsyncClient(
        timeout=12.0, transport=create_safe_async_transport(), trust_env=False,
    ) as client:
        response = await safe_client_get(
            client, capability.url,
            headers={"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15"},
            max_bytes=2 * 1024 * 1024,
        )
    if response.status_code != 200:
        raise ValueError("Short link resolution failed")
    resolved = dedicated_parse_capability(response.url)
    if resolved.supported and resolved.platform == capability.platform:
        return resolved
    # The existing Weibo adapter also recognizes these IDs in its app share
    # page. Inspect only that first-party page, never arbitrary redirected HTML.
    if capability.platform == "weibo" and urlsplit(response.url).hostname == "mapp.api.weibo.cn":
        match = re.search(r'"mblogid":\s*"([A-Za-z0-9]+)"|\bbid=([A-Za-z0-9]+)', response.text)
        if match:
            return dedicated_parse_capability(f"https://weibo.com/detail/{match[1] or match[2]}")
    return ParseCapability(capability.url, reason="unsupported_redirect")
