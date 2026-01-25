# API Testing Guide

## Overview

API tests are organized by router/endpoint group, following the same modular pattern as adapter tests.

## Test Structure

```
tests/test_api/
├── __init__.py
├── test_system.py       # Health checks, system info
├── test_contents.py     # Content CRUD operations
├── test_distribution.py # Auto-distribution & Telegram
└── test_media.py        # Media proxy & serving
```

## Running API Tests

### Run all API tests
```bash
cd backend
python3 -m pytest tests/test_api/ -v
```

### Run specific module
```bash
python3 -m pytest tests/test_api/test_contents.py -v
python3 -m pytest tests/test_api/test_system.py -v
```

### Run specific test
```bash
python3 -m pytest tests/test_api/test_contents.py::TestContentsAPI::test_list_contents -v
```

## Test Fixtures

All API tests use the `client` fixture from `conftest.py`, which provides an authenticated AsyncClient with API token headers.

```python
@pytest.mark.asyncio
async def test_example(self, client: AsyncClient):
    response = await client.get("/api/v1/endpoint")
    assert response.status_code == 200
```

## Test Coverage

### System API (`test_system.py`)
- ✅ Health check endpoint
- ✅ API root endpoint
- ✅ System stats

### Contents API (`test_contents.py`)
- ✅ List contents with pagination
- ✅ Filter by platform/tags
- ✅ Create new content from URL
- ✅ Get content by ID
- ✅ Delete content
- ✅ Search contents

### Distribution API (`test_distribution.py`)
- ✅ Get distribution status
- ✅ Trigger manual distribution
- ✅ View distribution history

### Media API (`test_media.py`)
- ✅ Media proxy endpoint
- ✅ Stored media access

## Adding New API Tests

1. Identify the router module (contents, distribution, system, media)
2. Add tests to the corresponding `test_*.py` file
3. Use descriptive test names following pattern: `test_<action>_<entity>`
4. Leverage fixtures: `client`, `db_session`, `get_platform_urls`

Example:
```python
class TestContentsAPI:
    @pytest.mark.asyncio
    async def test_update_content_tags(self, client: AsyncClient):
        """Test PATCH /api/v1/contents/{id}/tags"""
        payload = {"tags": ["tag1", "tag2"]}
        response = await client.patch("/api/v1/contents/1/tags", json=payload)
        assert response.status_code == 200
```

## Integration with Adapter Tests

API tests often work together with adapter tests:
- Adapter tests verify parsing logic
- API tests verify endpoint behavior and data persistence

Run both together:
```bash
python3 -m pytest tests/test_adapters/ tests/test_api/ -v
```
