from typing import Optional
from app.adapters.base import PlatformAdapter, ParsedContent
from app.adapters.errors import NonRetryableAdapterError

class XiaohongshuAdapter(PlatformAdapter):
    async def detect_content_type(self, url: str) -> Optional[str]:
        return "note"

    async def clean_url(self, url: str) -> str:
        # Basic cleaning: remove query params
        return url.split("?")[0]

    async def parse(self, url: str) -> ParsedContent:
        # TODO: Implement actual parsing logic (Browser MCP reverse engineering required)
        raise NonRetryableAdapterError("Xiaohongshu parsing not implemented yet")
