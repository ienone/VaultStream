"""A slow external Weibo request must not stall unrelated API coroutines."""
import asyncio
import threading
import pytest
import requests
from app.adapters.weibo_parser import parse_weibo, parse_user

@pytest.mark.parametrize('parse,identifier', [(parse_weibo, 'fixture'), (parse_user, '123')])
async def test_weibo_network_wait_does_not_block_event_loop(monkeypatch, parse, identifier):
    released = threading.Event()
    observed = []
    def slow_get(*args, **kwargs):
        observed.append(released.wait(timeout=0.3))
        response = requests.Response()
        response.status_code = 404
        response.url = 'https://weibo.com/fixture'
        return response
    monkeypatch.setattr(requests, 'get', slow_get)
    async def unrelated_api_work():
        await asyncio.sleep(0.01)
        released.set()
    await asyncio.gather(parse(identifier, 'https://weibo.com/fixture', {}, {}),
        unrelated_api_work(), return_exceptions=True)
    assert observed and all(observed)
