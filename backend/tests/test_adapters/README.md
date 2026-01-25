# Testing Guide: Unified Adapter Tests

## Overview

The VaultStream backend now has a unified pytest-based testing framework for all platform adapters. Tests are organized under `tests/test_adapters/` with a common base class providing shared functionality.

## Running Tests

### Run all adapter tests
```bash
cd backend
python3 -m pytest tests/test_adapters/ -v
```

### Run specific platform
```bash
python3 -m pytest tests/test_adapters/test_bilibili.py -v
python3 -m pytest tests/test_adapters/test_twitter.py -v
python3 -m pytest tests/test_adapters/test_weibo.py -v
python3 -m pytest tests/test_adapters/test_zhihu.py -v
```

### Run specific test
```bash
python3 -m pytest tests/test_adapters/test_bilibili.py::TestBilibiliAdapter::test_url_normalization -v
```

### Skip integration tests (network-dependent)
```bash
python3 -m pytest tests/test_adapters/ -v -m "not integration"
```

## Test Structure

Each platform has a dedicated test module inheriting from `AdapterTestBase`:

- **test_bilibili.py**: Video, Article, Dynamic (Opus)
- **test_twitter.py**: Tweets (requires FxTwitter API)
- **test_weibo.py**: Status, User Profile
- **test_zhihu.py**: Answer, Article, Question, Pin
- **test_xiaohongshu.py**: Note, Video, User Profile

## Fixtures

### get_platform_urls
Queries the database for real test URLs by platform:

```python
@pytest.mark.asyncio
async def test_parse_from_db(self, adapter, get_platform_urls):
    urls = await get_platform_urls("bilibili", limit=5)
    for content_type, url in urls.items():
        result = await self._test_basic_parse(adapter, url)
```

If database is empty, tests will skip or use hardcoded fallback URLs.

## Adding New Platform Tests

1. Create `tests/test_adapters/test_<platform>.py`
2. Inherit from `AdapterTestBase`
3. Implement required properties:
   - `platform_name`
   - `adapter_class`
   - `get_test_urls()` (fallback URLs)
4. Use inherited test methods:
   - `_test_basic_parse()`
   - `_test_archive_structure()`
   - `_test_url_normalization()`

Example:
```python
from tests.test_adapters.base import AdapterTestBase
from app.adapters.my_platform import MyPlatformAdapter

class TestMyPlatformAdapter(AdapterTestBase):
    @property
    def platform_name(self) -> str:
        return "my_platform"
    
    @property
    def adapter_class(self):
        return MyPlatformAdapter
    
    def get_test_urls(self) -> Dict[str, str]:
        return {"article": "https://example.com/article/123"}
    
    @pytest.mark.asyncio
    async def test_parse_from_db(self, adapter, get_platform_urls):
        urls = await get_platform_urls(self.platform_name, limit=5)
        if not urls:
            pytest.skip(f"No {self.platform_name} URLs in database")
        
        for content_type, url in urls.items():
            result = await self._test_basic_parse(adapter, url)
            # Add platform-specific assertions
```

## Archive Builder Utilities

Adapters can now use `app.adapters.utils.archive_builder.ArchiveBuilder` for common operations:

```python
from app.adapters.utils.archive_builder import ArchiveBuilder

# Create base archive structure
archive = ArchiveBuilder.create_base_archive(
    content_type="platform_type",
    title="My Title",
    plain_text="Content",
    markdown="# Markdown content"
)

# Select best image quality from multi-resolution dict
url = ArchiveBuilder.select_best_image_url(pic_info)

# Add images/videos
ArchiveBuilder.add_image(archive, url, width=1920, height=1080)
ArchiveBuilder.add_video(archive, video_url, cover=cover_url)
```

This reduces code duplication and ensures consistency across adapters.
