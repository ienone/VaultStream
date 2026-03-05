import pytest
import json
import re
from unittest.mock import patch, MagicMock, AsyncMock
from app.adapters.utils.content_agent import process_content, ProcessResult

@pytest.mark.asyncio
class TestContentAgentFullPipeline:
    """
    Full pipeline test for ContentAgent mocking LLM responses.
    Verifies Layer 1 (Structure) -> Layer 2 (Metadata/Clean) -> Apply.
    """

    @patch("openai.AsyncOpenAI")
    async def test_process_content_full_pipeline(self, mock_openai_class):
        # 1. Setup Mock OpenAI Client
        mock_client = MagicMock()
        mock_openai_class.return_value = mock_client
        
        # Mock Layer 1 Response (Structural Scan)
        # Input MD has 10 lines. We want L4-L7 as body.
        layer1_json = {
            "body_start_line": 4,
            "body_end_line": 7,
            "metadata_blocks": [
                {"start_line": 1, "end_line": 3, "location": "header", "type": "navigation", "hint": "Top nav"},
                {"start_line": 8, "end_line": 10, "location": "footer", "type": "copyright", "hint": "Footer info"}
            ]
        }
        
        # Mock Layer 2 Response (Extract + Clean)
        layer2_json = {
            "common_fields": {
                "title": "测试文章标题",
                "author_name": "张三",
                "published_at": "2024-03-05"
            },
            "extension_fields": {
                "source": "单元测试"
            },
            "tags": ["AI", "测试"],
            "heading_fixes": [
                {"line": 4, "level": 1, "text": "修正后的主标题"}
            ],
            "lines_to_remove": [6], # Remove a noise line inside body
            "summary": "这是一篇用于测试全链路解析的文章。"
        }

        # Configure mock to return these in sequence
        mock_completion_1 = MagicMock()
        mock_completion_1.choices = [MagicMock(message=MagicMock(content=json.dumps(layer1_json)))]
        
        mock_completion_2 = MagicMock()
        mock_completion_2.choices = [MagicMock(message=MagicMock(content=json.dumps(layer2_json)))]
        
        mock_client.chat.completions.create = AsyncMock(side_effect=[mock_completion_1, mock_completion_2])

        # 2. Prepare "Dirty" Input Data
        # L1-3: Header noise
        # L4: Title (to be fixed)
        # L5: Good content
        # L6: Noise line inside body (to be removed)
        # L7: Good content
        # L8-10: Footer noise
        dirty_markdown = (
            "Home | News | About\n"
            "---导航栏结束---\n\n"
            "**原始标题**\n"
            "这是第一段真实内容。\n"
            "这是一行广告干扰代码：DEBUG_EXPIRED\n"
            "这是第二段真实内容。\n"
            "\n"
            "Copyright 2024\n"
            "All rights reserved."
        )
        
        mock_fetch_result = MagicMock()
        mock_fetch_result.content_type = "markdown"
        mock_fetch_result.content = dirty_markdown
        mock_fetch_result.source = "mock_fetcher"
        
        llm_config = {
            "provider": "openai/gpt-4o",
            "api_token": "sk-test",
            "base_url": "https://api.openai.com/v1"
        }

        # 3. Run Pipeline
        url = "https://test.com/article"
        result = await process_content(url, mock_fetch_result, llm_config, verbose=True)

        # 4. Assertions
        
        # Verify Metadata Extraction
        assert result.common_fields["title"] == "测试文章标题"
        assert result.common_fields["author_name"] == "张三"
        assert result.common_fields["source_tags"] == ["AI", "测试"]
        assert result.extension_fields["source"] == "单元测试"
        
        # Verify Cleaning (The Core Logic)
        # - Header (L1-3) should be gone
        # - Footer (L8-10) should be gone
        # - L6 (Noise line) should be gone
        # - L4 should be replaced by "# 修正后的主标题"
        
        cleaned = result.cleaned_markdown
        print(f"\nCleaned Markdown:\n{cleaned}")
        
        assert "Home | News" not in cleaned
        assert "Copyright 2024" not in cleaned
        assert "DEBUG_EXPIRED" not in cleaned
        assert "# 修正后的主标题" in cleaned
        assert "这是第一段真实内容。" in cleaned
        assert "这是第二段真实内容。" in cleaned
        
        # Verify LLM usage
        assert result.llm_calls == 2
        assert mock_client.chat.completions.create.call_count == 2
        
        # Check ops_log for traceability
        ops = [op["op"] for op in result.ops_log]
        assert "remove_header" in ops
        assert "remove_footer" in ops
        assert "remove_body_line" in ops
        assert "heading_fix" in ops
