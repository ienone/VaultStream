"""Deterministic titles for sources without a native title; never invent facts."""
import html
import re

from bs4 import BeautifulSoup

_PLACEHOLDERS = {'', '-', '无标题', '无正文内容'}


def needs_title(title: str | None) -> bool:
    return (title or '').strip() in _PLACEHOLDERS


def derive_title(body: str | None, limit: int = 60) -> str | None:
    if not body or not body.strip():
        return None
    source = body.strip()
    # Preserve block boundaries, and prefer an explicit heading at the start.
    soup = BeautifulSoup(source, 'html.parser')
    for tag in soup(['script', 'style']):
        tag.decompose()
    for br in soup.find_all('br'):
        br.replace_with('\n')
    for block in soup.find_all(['p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'blockquote']):
        block.append('\n')
    text = soup.get_text() if soup.find() else html.unescape(source)
    text = re.sub(r'!\[[^\]]*\]\([^)]*\)', '', text)
    text = re.sub(r'\[([^\]]+)\]\([^)]*\)', r'\1', text)
    text = re.sub(r'https?://\S+', '', text)
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        return None
    first = re.sub(r'^#{1,6}\s+|^>\s*', '', lines[0])
    first = re.sub(r'(\*\*|__|~~|`)(.+?)\1', r'\2', first)
    first = re.sub(r'(?<!\w)[*_]([^*_]+)[*_](?!\w)', r'\1', first).strip()
    first = re.sub(r'\s+', ' ', first)
    if not first:
        return None
    return first if len(first) <= limit else first[:limit].rstrip() + '…'
