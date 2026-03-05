import pytest
import os
import json
from unittest.mock import patch, AsyncMock, MagicMock
from app.adapters.universal_adapter import UniversalAdapter
from app.adapters.utils.content_agent import ProcessResult, ProcessResult
from app.adapters.base import ParsedContent, LAYOUT_ARTICLE

# Load real HTML data for testing
DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "universal")
ITHOME_HTML_PATH = os.path.join(DATA_DIR, "ithome_926158.html")

def load_ithome_html():
    if os.path.exists(ITHOME_HTML_PATH):
        with open(ITHOME_HTML_PATH, "r", encoding="utf-8") as f:
            return f.read()
    return "<html><body>Mock ITHome Content</body></html>"

@pytest.mark.asyncio
class TestUniversalAdapterOffline:
    """
    Offline tests for UniversalAdapter to verify orchestration logic
    without real network or LLM calls.
    """

    @patch("app.adapters.universal_adapter.tiered_fetch")
    @patch("app.adapters.universal_adapter.process_content")
    @patch("app.adapters.universal_adapter.LLMFactory.get_crawl4ai_config")
    async def test_parse_ithome_flow(self, mock_get_llm_config, mock_process_content, mock_tiered_fetch):
        # 1. Setup Mocks
        url = "https://www.ithome.com/0/926/158.htm"
        html_content = load_ithome_html()
        
        # Mock fetch result
        mock_fetch_result = MagicMock()
        mock_fetch_result.content_type = "html"
        mock_fetch_result.html = html_content
        mock_fetch_result.source = "direct_http"
        mock_tiered_fetch.return_value = mock_fetch_result
        
        # Mock LLM config
        mock_get_llm_config.return_value = {"provider": "openai/gpt-4o", "api_token": "test", "base_url": "test"}
        
        # Mock Process result
        mock_process_result = ProcessResult(
            cleaned_markdown="# IT之家文章标题\n\n这是正文内容。\n\n![图片](https://img.ithome.com/test.jpg)",
            original_markdown="# IT之家文章标题\n\n这是正文内容。\n\n![图片](https://img.ithome.com/test.jpg)",
            common_fields={
                "title": "IT之家测试文章",
                "author_name": "IT之家编辑",
                "published_at": "2026-03-05 12:00:00",
                "cover_url": "https://img.ithome.com/cover.jpg"
            },
            extension_fields={
                "source": "IT之家",
                "category": "科技"
            },
            ops_log=[{"op": "mock"}],
            fetch_source="direct_http",
            selector=".post-content",
            llm_calls=2
        )
        mock_process_content.return_value = mock_process_result
        
        # 2. Execute
        adapter = UniversalAdapter()
        # On Windows, _do_parse is called via thread pool but we want to test _do_parse directly for logic
        result = await adapter._do_parse(url)
        
        # 3. Assertions
        assert isinstance(result, ParsedContent)
        assert result.platform == "universal"
        assert result.title == "IT之家测试文章"
        assert result.author_name == "IT之家编辑"
        assert result.layout_type == LAYOUT_ARTICLE
        assert "https://img.ithome.com/test.jpg" in result.media_urls
        assert result.cover_url == "https://img.ithome.com/cover.jpg"
        assert result.archive_metadata["version"] == 3
        assert result.archive_metadata["fetch_source"] == "direct_http"
        assert result.archive_metadata["selector"] == ".post-content"
        
        # Verify calls
        mock_tiered_fetch.assert_called_once_with(url, cookies={}, verbose=True)
        mock_process_content.assert_called_once()

    @patch("app.adapters.universal_adapter.tiered_fetch")
    async def test_fetch_failure_handling(self, mock_tiered_fetch):
        # Setup mock to raise error
        mock_tiered_fetch.side_effect = Exception("Network Timeout")
        
        adapter = UniversalAdapter()
        from app.adapters.errors import RetryableAdapterError
        
        with pytest.raises(RetryableAdapterError) as excinfo:
            await adapter._do_parse("http://fail.com")
        
        assert "获取失败" in str(excinfo.value)
