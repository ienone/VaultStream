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


def format_push_text(content: dict, *, rich_text: bool) -> str:
    content = _outbound_content(content)
    mode = (content.get("render_config") or {}).get("format", "summary")
    title = str(content.get("title") or "").strip()
    body = str(content.get("body") or "").strip()
    summary = str(content.get("summary") or "").strip()
    if title and body.split("\n", 1)[0].strip() == title:
        body = body[len(title):].lstrip()
    if mode == "summary":
        body = body if body and len(body) <= 500 else (summary or body)
        if len(body) > 500:
            body = body[:500].rstrip() + "…"
    else:
        body = body or summary
    escape = html.escape if rich_text else str
    parts = []
    if title:
        parts.append(f"<b>{escape(title)}</b>" if rich_text else title)
    if body:
        parts.append(escape(body))
    footer = []
    if content.get("author_name"):
        footer.append(escape(str(content["author_name"])))
    url = content.get("clean_url") or content.get("canonical_url") or content.get("url")
    if url:
        footer.append(f'<a href="{html.escape(url, quote=True)}">原文</a>' if rich_text else url)
    if footer:
        parts.append(" · ".join(footer) if rich_text else "\n".join(footer))
    return "\n\n".join(parts)
