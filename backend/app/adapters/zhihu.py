from typing import Optional
from app.adapters.base import PlatformAdapter, ParsedContent
from app.adapters.errors import NonRetryableAdapterError

class ZhihuAdapter(PlatformAdapter):
    async def detect_content_type(self, url: str) -> Optional[str]:
        if "question" in url:
            return "question"
        if "article" in url:
            return "article"
        return "answer"

    async def clean_url(self, url: str) -> str:
        return url.split("?")[0]

    async def parse(self, url: str) -> ParsedContent:
        # TODO: Implement actual parsing logic
        raise NonRetryableAdapterError("Zhihu parsing not implemented yet")
