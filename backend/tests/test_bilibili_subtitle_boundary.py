"""Platform account cookies must never be forwarded to subtitle CDNs."""
import json
import httpx
from app.adapters.bilibili_parser.video_media import read_video_media
from app.core.safe_fetch import SafeFetchResult

async def test_subtitle_fetch_has_no_platform_credentials(monkeypatch):
    async def safe_get(client, url, **kwargs):
        assert not list(client.cookies.jar)
        assert 'cookie' not in client.headers
        assert 'authorization' not in client.headers
        assert kwargs['max_bytes'] == 4 * 1024 * 1024
        return SafeFetchResult(url, 200, httpx.Headers({'content-type': 'application/json'}),
            json.dumps({'body': [{'from': 0, 'to': 1, 'content': '字幕证据'}]}).encode())
    monkeypatch.setattr('app.adapters.bilibili_parser.video_media.safe_client_get', safe_get)
    def respond(request):
        assert request.url.params['cid'] == '222'
        if request.url.path.endswith('playurl'):
            data = {'durl': [{'url': 'https://example.com/video.mp4', 'size': 1024}]}
        else:
            data = {'bvid': 'BVfixture', 'cid': 222, 'view_points': [{'from': 0, 'to': 10, 'content': '章节'}],
                'subtitle': {'subtitles': [{'lan': 'ai-zh', 'subtitle_url': '//example.com/captions'}]}}
        return httpx.Response(200, json={'code': 0, 'data': data})
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond),cookies={'SESSDATA': 'fixture'}) as client:
        video, payload = await read_video_media(client, {'bvid': 'BVfixture', 'pages': [
            {'page': 1, 'cid': 111, 'duration': 100}, {'page': 2, 'cid': 222, 'duration': 20}]},
            'https://www.bilibili.com/video/BVfixture?p=2')
    assert video['source_identity'] == 'bilibili:BVfixture:222'
    assert video['duration_ms'] == 20000
    assert len(payload['chunks']) == 2
    assert payload['chunks'][1]['content'] == '字幕证据'
    assert payload['chunks'][1]['generated'] is True


def test_transcript_windows_preserve_original_text_and_times():
    from app.adapters.bilibili_parser.video_media import transcript_chunks
    cues = [{'from': i * 2, 'to': i * 2 + 1.5, 'content': f'原文第{i}句'} for i in range(40)]
    chunks = transcript_chunks(cues, identity='bilibili:fixture:1', language='ai-zh', duration=90)
    restored = [cue for chunk in chunks for cue in chunk['cues']]
    assert restored == [{'start_seconds': c['from'], 'end_seconds': c['to'], 'content': c['content']} for c in cues]
    assert '\n'.join(chunk['content'] for chunk in chunks) == '\n'.join(c['content'] for c in cues)
    assert all(chunk['start_seconds'] == chunk['cues'][0]['start_seconds']
        and chunk['end_seconds'] == chunk['cues'][-1]['end_seconds'] for chunk in chunks)
    assert len(chunks) < len(cues)


async def test_player_mismatched_video_does_not_produce_timepoints():
    def respond(request):
        data = {'durl': []} if request.url.path.endswith('playurl') else {
            'bvid': 'another-video', 'cid': 999,
            'view_points': [{'from': 0, 'to': 1, 'content': '别的视频'}]}
        return httpx.Response(200, json={'code': 0, 'data': data})
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        _, payload = await read_video_media(client, {'bvid': 'BVfixture',
            'pages': [{'page': 1, 'cid': 111, 'duration': 100}]}, 'https://www.bilibili.com/video/BVfixture')
    assert payload['chunks'] == []
    assert payload['media_status']['x/player/wbi/v2']['status'] == 'identity_mismatch'


async def test_player_cannot_substitute_a_different_declared_subtitle_track(monkeypatch):
    async def unexpected_fetch(*args, **kwargs):
        raise AssertionError('Unrelated subtitle must not be fetched')
    monkeypatch.setattr('app.adapters.bilibili_parser.video_media.safe_client_get', unexpected_fetch)
    def respond(request):
        data = {'durl': []} if request.url.path.endswith('playurl') else {
            'bvid': 'BVfixture', 'cid': 111,
            'subtitle': {'subtitles': [{'id': 999, 'lan': 'ai-zh', 'subtitle_url': '//example.com/foreign'}]}}
        return httpx.Response(200, json={'code': 0, 'data': data})
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        _, payload = await read_video_media(client, {'bvid': 'BVfixture',
            'pages': [{'page': 1, 'cid': 111, 'duration': 100}], 'subtitle': {'list': [{'id': 123}]}},
            'https://www.bilibili.com/video/BVfixture')
    assert payload['chunks'] == []
