import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/review/models/queue_item.dart';

void main() {
  group('QueueItem Model', () {
    test('fromJson should parse valid JSON correctly', () {
      final json = {
        'id': 10,
        'content_id': 100,
        'title': 'Test Item',
        'platform': 'bilibili',
        'tags': ['anime'],
        'is_nsfw': false,
        'status': 'will_push',
        'priority': 5,
      };

      final item = QueueItem.fromJson(json);

      expect(item.id, 10);
      expect(item.contentId, 100);
      expect(item.status, 'will_push');
      expect(item.priority, 5);
    });

    test('QueueStatus.fromValue should parse values correctly', () {
      expect(QueueStatus.fromValue('will_push'), QueueStatus.willPush);
      expect(QueueStatus.fromValue('filtered'), QueueStatus.filtered);
      expect(QueueStatus.fromValue('pending_review'), QueueStatus.pendingReview);
      expect(QueueStatus.fromValue('pushed'), QueueStatus.pushed);
      expect(QueueStatus.fromValue('unknown'), QueueStatus.filtered); // fallback
    });
  });
}
