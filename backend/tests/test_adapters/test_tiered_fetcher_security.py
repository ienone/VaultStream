from unittest.mock import AsyncMock, patch

import pytest

from app.adapters.utils import tiered_fetcher
from app.core.safe_fetch import UnsafeUrlError


@pytest.mark.asyncio
async def test_direct_http_returns_none_when_safe_fetch_blocks_url():
    with patch(
        "app.adapters.utils.tiered_fetcher.safe_client_get",
        AsyncMock(side_effect=UnsafeUrlError("blocked")),
    ) as mock_fetch:
        result = await tiered_fetcher._try_direct_http("http://127.0.0.1/internal")

    assert result is None
    mock_fetch.assert_awaited_once()


@pytest.mark.asyncio
async def test_crawl4ai_skips_unsafe_initial_url():
    async def _submit_inline(coro):
        return await coro

    with patch("app.adapters.utils.tiered_fetcher.is_safe_url", return_value=False):
        with patch("app.adapters.browser.browser_manager.submit_coro", AsyncMock(side_effect=_submit_inline)):
            with patch("app.adapters.browser.browser_manager.get_browser") as mock_get_browser:
                result = await tiered_fetcher._try_crawl4ai("http://127.0.0.1/internal")

    assert result is None
    mock_get_browser.assert_not_called()
