import asyncio

import pytest

from app.adapters import close_adapter, managed_adapter


class AsyncClosableAdapter:
    def __init__(self):
        self.closed = False

    async def close(self):
        self.closed = True


class SyncClosableAdapter:
    def __init__(self):
        self.closed = False

    def close(self):
        self.closed = True


def test_managed_adapter_closes_on_error():
    adapter = AsyncClosableAdapter()

    async def run():
        with pytest.raises(RuntimeError):
            async with managed_adapter(adapter):
                raise RuntimeError("parse failed")

    asyncio.run(run())

    assert adapter.closed is True


def test_close_adapter_supports_sync_close():
    adapter = SyncClosableAdapter()

    asyncio.run(close_adapter(adapter))

    assert adapter.closed is True
