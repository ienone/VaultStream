import pytest
from unittest.mock import patch, AsyncMock
from app.adapters.utils.tiered_fetcher import (
    _try_cloudflare_markdown, 
    _try_direct_http, 
    tiered_fetch,
    FetchResult
)
import httpx

# Helper to generate "sufficient" content that passes _has_sufficient_content check
def get_high_quality_html(title="Test Page"):
    return f"""
    <html>
        <head><title>{title}</title></head>
        <body>
            <article>
                <h1>{title}</h1>
                <p>{"This is a long paragraph that should help pass the quality check. " * 20}</p>
                <p>{"Another significant paragraph to ensure we have enough text blocks. " * 20}</p>
                <section>
                    <p>{"More content inside a section to mimic a real article structure." * 10}</p>
                </section>
            </article>
        </body>
    </html>
    """

@pytest.mark.asyncio
async def test_tiered_fetch_all_fail(httpx_mock):
    """
    Test that tiered_fetch raises RuntimeError when all 3 tiers fail.
    """
    url = "https://example.com/fail-all"
    
    # Mock Tier 1 & 2 to return 404 (which makes them return None internally)
    httpx_mock.add_response(url=url, status_code=404) # Tier 1
    httpx_mock.add_response(url=url, status_code=404) # Tier 2
    
    # Mock Tier 3 (crawl4ai) to return None
    with patch("app.adapters.utils.tiered_fetcher._try_crawl4ai", AsyncMock(return_value=None)):
        with pytest.raises(RuntimeError) as excinfo:
            await tiered_fetch(url)
        assert "All fetch methods failed" in str(excinfo.value)

@pytest.mark.asyncio
async def test_tiered_fetch_fallback_to_tier2(httpx_mock):
    """
    Test fallback from Tier 1 (fail) to Tier 2 (success).
    """
    url = "https://example.com/fallback"
    
    # Tier 1 fails (not markdown)
    httpx_mock.add_response(
        url=url, 
        status_code=200, 
        headers={"Content-Type": "text/html"}, # Not text/markdown
        text=get_high_quality_html("Tier 1 Failure")
    )
    
    # Tier 2 succeeds (passes quality check now)
    httpx_mock.add_response(
        url=url, 
        status_code=200, 
        text=get_high_quality_html("Tier 2 Success")
    )
    
    # Patch Tier 3 just in case, though it shouldn't be reached
    with patch("app.adapters.utils.tiered_fetcher._try_crawl4ai", AsyncMock(return_value=None)):
        result = await tiered_fetch(url)
        assert result.source == "direct_http"
        assert result.status_code == 200
        assert "Tier 2 Success" in result.content

@pytest.mark.asyncio
async def test_tiered_fetch_insufficient_content_trigger_next_tier(httpx_mock):
    """
    Test that low quality HTML in Tier 2 triggers fallback to Tier 3.
    """
    url = "https://example.com/low-quality"
    
    # Tier 1: Not markdown
    httpx_mock.add_response(url=url, status_code=200, headers={"Content-Type": "text/html"}, text="No MD")
    
    # Tier 2: 200 OK but junk content (empty body)
    httpx_mock.add_response(url=url, status_code=200, text="<html><body>Too short</body></html>")
    
    # Tier 3: Success
    mock_result = FetchResult(url=url, content="Quality content from browser", content_type="html", source="crawl4ai")
    with patch("app.adapters.utils.tiered_fetcher._try_crawl4ai", AsyncMock(return_value=mock_result)):
        result = await tiered_fetch(url)
        assert result.source == "crawl4ai"

@pytest.mark.asyncio
async def test_direct_http_500_error(httpx_mock):
    """Test Tier 2 handling of 500 error."""
    url = "https://example.com/error500"
    httpx_mock.add_response(url=url, status_code=500)
    
    result = await _try_direct_http(url)
    assert result is None

@pytest.mark.asyncio
async def test_cloudflare_md_malformed_header(httpx_mock):
    """Test Tier 1 with content-type but invalid markdown."""
    url = "https://example.com/bad-md"
    httpx_mock.add_response(
        url=url,
        status_code=200,
        headers={"Content-Type": "text/markdown"},
        text="just some text without any markdown markers"
    )
    
    result = await _try_cloudflare_markdown(url)
    assert result is None # Should fail _is_valid_markdown
