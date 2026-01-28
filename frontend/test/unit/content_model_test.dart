import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/collection/models/content.dart';

void main() {
  group('ContentDetail Model Test', () {
    test('fromJson should parse valid JSON correctly', () {
      final json = {
        'id': 1,
        'url': 'https://example.com',
        'title': 'Test Content',
        'platform': 'twitter',
        'status': 'archived',
        'created_at': '2024-01-01T12:00:00Z',
        'updated_at': '2024-01-01T12:00:00Z',
        'tags': ['tag1', 'tag2'],
        'is_nsfw': false,
        'has_video': false,
        'media': [],
      };

      final content = ContentDetail.fromJson(json);

      expect(content.id, 1);
      expect(content.title, 'Test Content');
      expect(content.platform, 'twitter');
      expect(content.tags, ['tag1', 'tag2']);
      expect(content.isNsfw, false);
    });

    test('fromJson should handle null optional fields', () {
      final json = {
        'id': 2,
        'url': 'https://example.com/2',
        'platform': 'bilibili',
        'status': 'pending',
        'created_at': '2024-01-01T12:00:00Z',
        'updated_at': '2024-01-01T12:00:00Z',
        'tags': [],
        'is_nsfw': false,
        'has_video': false,
        'media': [],
      };

      final content = ContentDetail.fromJson(json);

      expect(content.id, 2);
      expect(content.title, null);
      expect(content.description, null);
      expect(content.coverUrl, null);
    });
  });
}
