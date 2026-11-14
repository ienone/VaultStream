import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/sse_service.dart';
import 'notification_models.dart';

typedef NotificationQuery = ({String? category, String state, int offset});

final notificationUnreadCountProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  refreshOnEvents(ref, (event) => event.type == 'notification_updated');
  final response = await ref
      .watch(apiClientProvider)
      .get<int>('/notifications/unread-count');
  return response.data!;
});

final notificationInboxProvider = FutureProvider.autoDispose
    .family<NotificationInbox, NotificationQuery>((ref, query) async {
      refreshOnEvents(ref, (event) => event.type == 'notification_updated');

      final dio = ref.watch(apiClientProvider);
      final response = await dio.get(
        '/notifications',
        queryParameters: {
          'state': query.state,
          if (query.category != null) 'category': query.category,
          'limit': 100,
          'offset': query.offset,
        },
      );
      return NotificationInbox.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    });

Future<void> applyNotificationAction(
  WidgetRef ref,
  int notificationId,
  String action, {
  DateTime? snoozedUntil,
}) async {
  final dio = ref.read(apiClientProvider);
  await dio.post(
    '/notifications/$notificationId/actions',
    data: {
      'action': action,
      if (snoozedUntil != null)
        'snoozed_until': snoozedUntil.toUtc().toIso8601String(),
    },
  );
  ref.invalidate(notificationInboxProvider);
  ref.invalidate(notificationUnreadCountProvider);
}

Future<void> markAllNotificationsRead(WidgetRef ref) async {
  await ref.read(apiClientProvider).post('/notifications/read-all');
  ref.invalidate(notificationInboxProvider);
  ref.invalidate(notificationUnreadCountProvider);
}

Future<Map<String, dynamic>> generateNotificationDigest(WidgetRef ref) async {
  final response = await ref
      .read(apiClientProvider)
      .post('/notifications/digest');
  ref.invalidate(notificationInboxProvider);
  ref.invalidate(notificationUnreadCountProvider);
  return Map<String, dynamic>.from(response.data as Map);
}
