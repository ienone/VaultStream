import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/review/models/queue_item.dart';

void main() {
  group('QueueItem Model', () {
    test('fromJson should parse valid JSON correctly', () {
      final json = {
        'id': 10,
        'content_id': 100,
        'title': 'Test Item',
        'target_platform': 'bilibili',
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

    test('displayReason should map from reason_code when reason is empty', () {
      final json = {
        'id': 11,
        'content_id': 101,
        'target_platform': 'telegram',
        'status': 'filtered',
        'reason_code': 'manual_filtered',
      };

      final item = QueueItem.fromJson(json);
      expect(item.reasonCode, 'manual_filtered');
      expect(item.displayReason, '已手动过滤');
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
