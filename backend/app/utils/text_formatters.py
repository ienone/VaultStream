"""
文本格式化工具模块

提供Telegram等平台的内容文本格式化功能
"""
import html
import re
from bs4 import BeautifulSoup
from markdown_it import MarkdownIt
from urllib.parse import urlsplit


def strip_markdown(text: str) -> str:
    """Readable outbound text; attachments travel through media_items, never URIs."""
    if not text:
        return text
    soup = BeautifulSoup(MarkdownIt().render(text), "html.parser")
    for node in soup.find_all(["img", "script", "style"]):
        node.decompose()
    for node in soup.find_all("a"):
        href = node.get("href", "")
        scheme = urlsplit(href).scheme
        if scheme in {"local", "file", "vaultstream"}:
            node.decompose()
        elif scheme in {"http", "https"} and node.get_text().strip() != href:
            node.append(f"（{href}）")
    for node in soup.find_all("br"):
        node.replace_with("\n")
    for node in soup.find_all(["p", "div", "li", "blockquote", "pre", "h1", "h2", "h3", "h4", "h5", "h6"]):
        node.append("\n")
    value = soup.get_text()
    value = re.sub(r"(?:local|file|vaultstream)://[^\s<>]+", "", value)
    return re.sub(r"\n{3,}", "\n\n", value).strip()


def _outbound_content(content: dict) -> dict:
    content = dict(content)
    for field in ("title", "body", "summary"):
        if content.get(field):
            content[field] = strip_markdown(str(content[field]))
    for field in ("url", "canonical_url", "clean_url"):
        if urlsplit(str(content.get(field) or "")).scheme not in {"http", "https"}:
            content[field] = ""
    return content


def select_push_media(content: dict) -> list[dict]:
    """The three formats share the same media selection on every platform."""
    mode = (content.get("render_config") or {}).get("format", "summary")
    items = list(content.get("media_items") or [])
    if mode == "text":
        return []
    if mode == "summary":
        photos = [item for item in items if item["type"] == "photo"]
        return photos[:1] or items[:1]
    return items


def truncate_message_body(text: str, limit: int) -> str:
    """Keep a readable excerpt without splitting a sentence when possible."""
    if len(text) <= limit:
        return text
    excerpt = text[:limit]
    boundaries = list(re.finditer(r"\n|[。！？!?](?:\s|$)", excerpt))
    if boundaries and boundaries[-1].end() >= limit // 2:
        excerpt = excerpt[:boundaries[-1].end()]
    return excerpt.rstrip() + "…\n\n正文已截断，查看原文。"


def format_push_stats(content: dict) -> str:
    """Use each parser's metric meanings, including non-post content types."""
    platform = content.get("platform")
    kind = content.get("content_type")
    stats = content.get("stats") or {}
    fields = []
    if platform == "bilibili":
        if kind == "live":
            fields = [("view", "人气值")]
        elif kind == "dynamic":
            fields = [("like", "点赞数"), ("reply", "评论数"), ("share", "转发数")]
        else:
            fields = [("view", "播放量" if kind in {"video", "bangumi"} else "阅读量"),
                      ("danmaku", "弹幕数"), ("like", "点赞数"), ("coin", "投币数"),
                      ("favorite", "收藏数"), ("reply", "评论数"), ("share", "分享数")]
    elif platform == "weibo":
        fields = ([("followers", "粉丝数"), ("friends", "关注数"), ("statuses", "微博数")]
                  if kind == "user_profile" else
                  [("like", "点赞数"), ("reply", "评论数"), ("share", "转发数")])
    elif platform == "twitter":
        fields = [("view", "浏览量"), ("like", "点赞数"), ("reply", "回复数"),
                  ("share", "转发数"), ("bookmarks", "书签数")]
    elif platform == "xiaohongshu":
        fields = ([("followers", "粉丝数"), ("following", "关注数"), ("liked", "获赞与收藏数")]
                  if kind == "user_profile" else
                  [("like", "点赞数"), ("favorite", "收藏数"), ("reply", "评论数"), ("share", "分享数")])
    elif platform == "zhihu":
        if kind == "question":
            fields = [("view", "浏览量"), ("reply", "回答数"), ("favorite", "关注数"),
                      ("comment_count", "评论数")]
        elif kind == "user_profile":
            fields = [("follower_count", "粉丝数"), ("following_count", "关注数"),
                      ("voteup_count", "获赞数"), ("thanked_count", "获感谢数"),
                      ("favorited_count", "被收藏数"), ("answer_count", "回答数"),
                      ("articles_count", "文章数"), ("pins_count", "想法数"), ("question_count", "提问数")]
        elif kind == "column":
            fields = [("view", "关注数"), ("reply", "文章数"), ("like", "赞同数")]
        elif kind == "collection":
            fields = [("view", "浏览量"), ("favorite", "关注数"), ("item_count", "内容数"),
                      ("like", "点赞数"), ("reply", "评论数")]
        else:
            fields = [("like", "赞同数" if kind in {"answer", "article"} else "点赞数"),
                      ("favorite", "收藏数"), ("reply", "评论数"),
                      ("thanks_count", "感谢数"), ("share", "转发数")]
    elif platform == "telegram":
        fields = [("telegram_views", "浏览量")]
    elif platform == "universal":
        fields = [("view_count", "浏览量"), ("like_count", "点赞数"),
                  ("collect_count", "收藏数"), ("comment_count", "评论数"), ("share_count", "分享数")]
    lines = [f"{label}：{stats[key]}" for key, label in fields
             if key in stats and stats[key] is not None and stats[key] != ""]
    if platform == "telegram" and stats.get("reactions"):
        from app.adapters.base import PlatformAdapter
        counts = [item["count"] for item in stats["reactions"] if item.get("count") not in (None, "")]
        if counts:
            approximate = any(re.search(r"[kKmM万亿]", str(count)) for count in counts)
            label = "回应数（约）" if approximate else "回应数"
            lines.append(f"{label}：{sum(PlatformAdapter._to_int(count) for count in counts)}")
    return "\n".join(lines)


def format_push_text(content: dict, *, rich_text: bool) -> str:
    content = _outbound_content(content)
    mode = (content.get("render_config") or {}).get("format", "summary")
    title = str(content.get("title") or "").strip()
    body = str(content.get("body") or "").strip()
    summary = str(content.get("summary") or "").strip()
    body_label = content.get("body_label") or ("简介" if content.get("content_type") == "video" else "正文")
    if title and body.split("\n", 1)[0].strip() == title:
        body = body[len(title):].lstrip()
    if mode == "summary":
        if summary and (not body or len(body) > 500):
            body_label = "摘要"
        body = body if body and len(body) <= 500 else (summary or body)
        body = truncate_message_body(body, 500)
    else:
        if not body and summary:
            body_label = "摘要"
        body = body or summary
    escape = html.escape if rich_text else str
    parts = []
    if title:
        labeled_title = f"标题：{escape(title)}"
        parts.append(f"<b>{labeled_title}</b>" if rich_text else labeled_title)
    if body:
        parts.append(f"{escape(body_label)}：{escape(body)}")
    statistics = format_push_stats(content)
    if statistics:
        parts.append(escape(statistics))
    footer = []
    if content.get("author_name"):
        footer.append(escape(str(content["author_name"])))
    url = content.get("clean_url") or content.get("canonical_url") or content.get("url")
    if url:
        footer.append(f'<a href="{html.escape(url, quote=True)}">原文</a>' if rich_text else url)
    if footer:
        parts.append(" · ".join(footer) if rich_text else "\n".join(footer))
    return "\n\n".join(parts)
