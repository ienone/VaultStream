"""Zhihu's anonymous Tardis reader, verified against the normal public page."""

import json
import re
from urllib.parse import urlsplit

from bs4 import BeautifulSoup

from app.adapters.base import LAYOUT_ARTICLE, ParsedContent
from .base import extract_images, preprocess_zhihu_html
from markdownify import markdownify


def parse_public_reader(html: str, url: str, kind: str, content_id: str) -> ParsedContent | None:
    soup = BeautifulSoup(html, "html.parser")
    payload = None
    for script in soup.find_all("script"):
        match = re.search(r"\bwindow\.g_initialProps\s*=\s*", script.string or "")
        if match:
            try:
                payload, _ = json.JSONDecoder().raw_decode(script.string[match.end():])
            except (ValueError, TypeError):
                return None
            break
    if not isinstance(payload, dict):
        return None
    data = payload.get("renderHtml")
    expected_type = {"answer": "ans", "article": "art"}.get(kind)
    if not isinstance(data, dict) or data.get("type") != expected_type:
        return None
    # The reader does not expose an id field. Its app link identifies the object;
    # answer links use /question/{answer_id}, not the parent question id.
    deep_link_url = data.get("deeplink_url")
    if not isinstance(deep_link_url, str):
        return None
    try:
        deep_link = urlsplit(deep_link_url)
    except ValueError:
        return None
    object_path = "question" if kind == "answer" else "articles"
    if deep_link.hostname != "oia.zhihu.com" or deep_link.path != f"/{object_path}/{content_id}":
        return None
    title, content = data.get("title"), data.get("content")
    if not isinstance(title, str) or not title.strip() or not isinstance(content, str):
        return None
    content = preprocess_zhihu_html(content)
    images = extract_images(content)
    text = BeautifulSoup(content, "html.parser").get_text("\n", strip=True)
    if not text and not images:
        return None
    author = data.get("author")
    if not isinstance(author, dict):
        return None
    context = None
    if kind == "answer":
        question_id = str(data.get("question_token") or "")
        requested_question = re.search(r"/question/(\d+)/answer/", url)
        if not question_id.isdigit() or (
            requested_question and requested_question.group(1) != question_id
        ):
            return None
        context = {
            "type": "question", "id": question_id, "title": title,
            "url": f"https://www.zhihu.com/question/{question_id}",
            "stats": {"answer_count": data.get("answer_count", 0)},
        }
    markdown = markdownify(content, heading_style="ATX")
    archive = {
        "version": 2, "type": f"zhihu_{kind}", "title": title,
        "plain_text": text, "markdown": markdown,
        "images": [{"url": image} for image in images], "links": [],
    }
    avatar = author.get("logo")
    if avatar:
        archive["images"].append({"url": avatar, "type": "avatar"})
    return ParsedContent(
        platform="zhihu", content_type=kind, content_id=content_id, clean_url=url,
        layout_type=LAYOUT_ARTICLE, title=f"回答：{title}" if kind == "answer" else title,
        body=markdown, author_name=author.get("name"), author_avatar_url=avatar,
        cover_url=images[0] if images else None, media_urls=images, context_data=context,
        stats={
            "like": data.get("upvoted_count", 0), "reply": data.get("comment_count", 0),
            "favorite": data.get("favorites", 0), "voteup_count": data.get("upvoted_count", 0),
            "comment_count": data.get("comment_count", 0),
            "favorited_count": data.get("favorites", 0),
        },
        # In the verified answer, Tardis 'created' equals desktop updatedTime.
        # Do not mislabel it as published_at or invent an absent author id.
        archive_metadata={
            "version": 2, "source": "zhihu_public_reader",
            "reader_timestamp": data.get("created"), "processed_archive": archive,
        },
    )
