from typing import Optional
from app.adapters.base import PlatformAdapter, ParsedContent
from app.adapters.errors import NonRetryableAdapterError

class WeiboAdapter(PlatformAdapter):
    async def detect_content_type(self, url: str) -> Optional[str]:
        return "status"

    async def clean_url(self, url: str) -> str:
        return url.split("?")[0]

    async def parse(self, url: str) -> ParsedContent:
        # TODO: Implement actual parsing logic
        raise NonRetryableAdapterError("Weibo parsing not implemented yet")
