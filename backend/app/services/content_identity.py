"""URL identity shared by capture, monitored links, and favorite imports."""
from dataclasses import dataclass
from urllib.parse import parse_qs, unquote, urlencode, urlsplit, urlunsplit

from app.adapters import AdapterFactory
from app.adapters.weibo import WeiboAdapter
from app.models import Content, Platform
from app.services.parse_capabilities import dedicated_parse_capability, resolve_dedicated_parse_capability
from app.utils.url_utils import (
    canonicalize_url, extract_primary_url_candidate, is_url_like_input, normalize_bilibili_url,
    normalize_url_for_dedup,
)


class InvalidShareInput(ValueError):
    pass


def canonical_link(url: str) -> tuple[Platform, str]:
    """Identify an HTTP link without contacting its publisher."""
    platform = AdapterFactory.detect_platform(url)
    capability = dedicated_parse_capability(url)
    target = urlsplit(capability.url if capability.supported else url)
    path = target.path
    query = target.query
    if platform == Platform.BILIBILI:
        params = parse_qs(query, keep_blank_values=True)
        query = ""
        if "p" in params:
            try:
                page = int(params["p"][0])
            except ValueError as error:
                raise InvalidShareInput("无效的视频分 P 参数") from error
            if page < 1:
                raise InvalidShareInput("无效的视频分 P 参数")
            if page != 1:
                query = urlencode({"p": page})
        if capability.content_type == "video":
            target = target._replace(netloc="www.bilibili.com")
    elif platform == Platform.XIAOHONGSHU and capability.supported:
        path = path.replace("/discovery/item/", "/explore/")
        query = ""
    elif platform in {Platform.TWITTER, Platform.ZHIHU, Platform.TELEGRAM, Platform.WEIBO}:
        query = ""
        if platform == Platform.WEIBO and capability.content_type == "status":
            path = "/detail/" + WeiboAdapter._numeric_status_id(path.rsplit("/", 1)[-1])
    return platform, normalize_url_for_dedup(urlunsplit(target._replace(path=path, query=query)))


@dataclass(frozen=True)
class ContentLink:
    url: str
    platform: Platform
    canonical: str

    @classmethod
    async def resolve(cls, raw: str) -> "ContentLink":
        candidate = extract_primary_url_candidate(raw)
        if not is_url_like_input(candidate):
            raise InvalidShareInput("未识别到链接，请粘贴网址或平台分享内容")
        url = canonicalize_url(normalize_bilibili_url(candidate))
        if unquote(urlsplit(url).path).lower().endswith(".pdf"):
            raise InvalidShareInput("不支持保存 PDF 文件")
        capability = dedicated_parse_capability(url)
        if capability.short_link:
            expanded = await resolve_dedicated_parse_capability(url)
            if expanded.supported:
                platform, canonical = canonical_link(expanded.url)
                return cls(url, platform, canonical)
        platform, canonical = canonical_link(url)
        return cls(url, platform, canonical)

    def matches(self):
        return (Content.platform == self.platform) & (Content.canonical_url == self.canonical)
