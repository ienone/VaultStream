"""ContentService tag normalization tests."""

from app.services.content_service import ContentService


def test_normalize_tags_merge_and_deduplicate():
    tags = ["技术", "  收藏  ", "", "AI,机器学习", "AI"]
    tags_text = "前端，后端  AI\n学习"

    normalized = ContentService._normalize_tags(tags, tags_text)

    assert normalized == [
        "技术",
        "收藏",
        "AI",
        "机器学习",
        "前端",
        "后端",
        "学习",
    ]


def test_normalize_tags_empty_input():
    assert ContentService._normalize_tags(None, None) == []
    assert ContentService._normalize_tags([], "   , ，  \n") == []
