"""Read native Bilibili media and timed text without downloading the video."""
import json
import math

from urllib.parse import parse_qs, urlparse

import httpx

from app.adapters.errors import NonRetryableAdapterError
from app.core.safe_fetch import safe_client_get


def transcript_chunks(cues: list, *, identity: str, language: str, duration: float) -> list[dict]:
    """Keep exact cues inside readable search windows (up to 30 seconds/800 chars)."""
    chunks = []
    current = None
    previous_start = -1.0
    for cue in cues:
        start, end, text = cue.get('from'), cue.get('to'), cue.get('content')
        if (not isinstance(start, (int, float)) or isinstance(start, bool)
                or not isinstance(end, (int, float)) or isinstance(end, bool)
                or not math.isfinite(start) or not math.isfinite(end)
                or not 0 <= start < end <= duration or start < previous_start
                or not isinstance(text, str)):
            raise ValueError('Invalid subtitle time slice')
        previous_start = start
        if not text.strip():
            continue
        if (current is None or end - current['start_seconds'] > 30
                or len(current['content']) + len(text) + 1 > 800
                or start - current['end_seconds'] > 5):
            current = {'source_identity': identity, 'segment_type': 'transcript',
                'start_seconds': start, 'end_seconds': end, 'content': '',
                'source': 'bilibili', 'language': language,
                'title': '平台 AI 字幕' if language.startswith('ai-') else '平台字幕',
                'generated': language.startswith('ai-'), 'cues': []}
            chunks.append(current)
        current['content'] += ('\n' if current['content'] else '') + text
        current['end_seconds'] = max(current['end_seconds'], end)
        current['cues'].append({'start_seconds': start, 'end_seconds': end, 'content': text})
    return chunks


async def read_video_media(client: httpx.AsyncClient, item: dict, url: str) -> tuple[dict, dict]:
    try:
        page_number = int(parse_qs(urlparse(url).query).get('p', ['1'])[0])
    except ValueError as exc:
        raise NonRetryableAdapterError('视频分 P 参数无效') from exc
    page = next((p for p in item.get('pages', []) if p.get('page') == page_number), None)
    if page is None:
        raise NonRetryableAdapterError('请求的视频分 P 不存在')
    cid = page['cid']
    identity = f"bilibili:{item['bvid']}:{cid}"
    video = {'source_identity': identity, 'duration_ms': page['duration'] * 1000}
    payload = {'chunks': [], 'media_status': {}, 'video_page': page_number,
               'video_page_title': page.get('part'), 'video_page_count': len(item.get('pages', []))}

    async def read_api(path: str, extra: dict) -> dict | None:
        try:
            response = await client.get('https://api.bilibili.com/' + path,
                params={'bvid': item['bvid'], 'cid': cid, **extra})
            response.raise_for_status()
            result = response.json()
            if result.get('code') != 0:
                payload['media_status'][path] = {'status': 'unavailable', 'code': result.get('code')}
                return None
            if not isinstance(result.get('data'), dict):
                raise ValueError('Invalid data')
            payload['media_status'][path] = {'status': 'available'}
            return result['data']
        except (httpx.HTTPError, ValueError) as exc:
            # Do not retain signed URLs, cookies or response text in errors.
            payload['media_status'][path] = {'status': 'failed', 'error_type': type(exc).__name__}
            return None

    playback = await read_api('x/player/playurl', {'qn': 32, 'fnval': 1, 'platform': 'html5'})
    if playback:
        streams = playback.get('durl', [])
        if len(streams) == 1 and isinstance(streams[0].get('url'), str):
            video['url'] = streams[0]['url']
            video['size'] = streams[0].get('size')
        else:
            payload['media_status']['x/player/playurl'] = {'status': 'unsupported_stream_layout'}
    player = await read_api('x/player/wbi/v2', {})
    if player and (player.get('bvid') != item['bvid'] or player.get('cid') != cid):
        payload['media_status']['x/player/wbi/v2'] = {'status': 'identity_mismatch'}
        player = None
    if player:
        for chapter in player.get('view_points', []):
            payload['chunks'].append({'source_identity': identity, 'segment_type': 'chapter',
                'start_seconds': chapter.get('from'), 'end_seconds': chapter.get('to'),
                'title': chapter.get('content'), 'content': chapter.get('content'), 'source': 'bilibili'})
        subtitles = (player.get('subtitle') or {}).get('subtitles', [])
        expected_tracks = {str(track['id']) for track in (item.get('subtitle') or {}).get('list', []) if 'id' in track}
        if expected_tracks:
            subtitles = [track for track in subtitles if str(track.get('id')) in expected_tracks]
        # Prefer Chinese human captions, then platform AI Chinese, then another available language.
        subtitles = sorted(subtitles, key=lambda s: (not s.get('lan', '').removeprefix('ai-').startswith('zh'), s.get('lan', '').startswith('ai-')))
        track = next((s for s in subtitles if s.get('subtitle_url')), None)
        if track:
            subtitle_url = track['subtitle_url']
            if subtitle_url.startswith('//'):
                subtitle_url = 'https:' + subtitle_url
            try:
                # Subtitle CDN requests never inherit the platform account cookies.
                async with httpx.AsyncClient(timeout=20) as public_client:
                    response = await safe_client_get(public_client, subtitle_url, max_bytes=4 * 1024 * 1024)
                if response.status_code != 200:
                    raise ValueError('Subtitle HTTP failure')
                cues = json.loads(response.content)['body']
                if not isinstance(cues, list):
                    raise ValueError('Invalid subtitle body')
                language = track.get('lan', '')
                payload['chunks'].extend(transcript_chunks(cues, identity=identity,
                    language=language, duration=page['duration']))
                payload['media_status']['subtitle'] = {'status': 'available', 'language': language, 'cues': len(cues)}
            except (httpx.HTTPError, ValueError, KeyError) as exc:
                payload['media_status']['subtitle'] = {'status': 'failed', 'error_type': type(exc).__name__}
        else:
            payload['media_status']['subtitle'] = {'status': 'unavailable'}
    return video, payload
