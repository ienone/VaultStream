import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/collection/models/content.dart';
import 'package:frontend/features/collection/utils/content_parser.dart';

void main() {
  test('详情图片使用统一资产首选 URL 并保留后续候选', () {
    final detail = ContentDetail.fromJson({
      'id': 9,
      'platform': 'test',
      'url': 'https://example.test/post/9',
      'status': 'completed',
      'tags': <String>[],
      'is_nsfw': false,
      'created_at': '2026-07-26T12:00:00Z',
      'updated_at': '2026-07-26T12:00:00Z',
      'cover_url': 'https://legacy.test/cover.jpg',
      'media_urls': ['https://legacy.test/body.jpg'],
      'media_assets': [
        {
          'id': 90,
          'content_id': 9,
          'media_type': 'image',
          'role': 'body',
          'position': 0,
          'sources': [
            {
              'url': 'http://server.test/body.webp?signature=x',
              'source_kind': 'local_signed',
            },
            {
              'url': 'https://origin.test/body.jpg',
              'source_kind': 'remote_direct',
            },
          ],
        },
      ],
    });

    expect(ContentParser.extractAllImages(detail, 'http://server.test'), [
      'http://server.test/body.webp?signature=x',
    ]);
    expect(ContentParser.extractImageFallbacks(detail), {
      'http://server.test/body.webp?signature=x': [
        'https://origin.test/body.jpg',
      ],
    });
    expect(
      ContentParser.imageCandidatesForUrl(
        detail,
        'https://origin.test/body.jpg',
        'http://server.test',
      ),
      [
        'http://server.test/body.webp?signature=x',
        'https://origin.test/body.jpg',
      ],
    );
  });
}
