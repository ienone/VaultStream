"""
Tests for URL normalization / dedup (Step 2)
"""
import pytest
from app.utils.url_utils import normalize_url_for_dedup


class TestNormalizeUrlForDedup:
    """normalize_url_for_dedup 去重规范化测试"""

    def test_empty_and_none(self):
        assert normalize_url_for_dedup("") == ""
        assert normalize_url_for_dedup("   ") == ""

    def test_strips_www(self):
        result = normalize_url_for_dedup("https://www.example.com/article")
        assert result == "https://example.com/article"

    def test_strips_trailing_slash(self):
        result = normalize_url_for_dedup("https://example.com/article/")
        assert result == "https://example.com/article"

    def test_strips_fragment(self):
        result = normalize_url_for_dedup("https://example.com/page#section")
        assert result == "https://example.com/page"

    def test_strips_utm_params(self):
        result = normalize_url_for_dedup(
            "https://example.com/post?utm_source=twitter&utm_medium=social&id=123"
        )
        assert result == "https://example.com/post?id=123"

    def test_http_to_https(self):
        result = normalize_url_for_dedup("http://example.com/page")
        assert result == "https://example.com/page"

    def test_no_scheme_defaults_https(self):
        result = normalize_url_for_dedup("example.com/page")
        assert result == "https://example.com/page"

    def test_host_lowercased(self):
        result = normalize_url_for_dedup("https://EXAMPLE.COM/Path")
        assert result == "https://example.com/Path"

    def test_combined_normalization(self):
        """www + trailing slash + fragment + utm 同时出现"""
        result = normalize_url_for_dedup(
            "http://www.Example.COM/article/?utm_source=rss#comments"
        )
        assert result == "https://example.com/article"

    def test_same_url_different_forms_dedup(self):
        """不同形式的同一 URL 规范化后应相等"""
        variants = [
            "https://www.example.com/post/123/",
            "http://www.example.com/post/123",
            "https://example.com/post/123/",
            "example.com/post/123/#top",
            "https://WWW.EXAMPLE.COM/post/123/?utm_campaign=feed",
        ]
        normalized = {normalize_url_for_dedup(v) for v in variants}
        assert len(normalized) == 1
        assert normalized.pop() == "https://example.com/post/123"

    def test_preserves_meaningful_query_params(self):
        result = normalize_url_for_dedup(
            "https://news.ycombinator.com/item?id=12345"
        )
        assert result == "https://news.ycombinator.com/item?id=12345"

    def test_root_path_no_trailing_slash(self):
        result = normalize_url_for_dedup("https://example.com/")
        assert result == "https://example.com"
