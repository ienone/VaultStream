import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/sse_service.dart';
import 'notification_models.dart';

typedef NotificationQuery = ({String? category, String state});

const NotificationQuery defaultNotificationQuery = (
  category: null,
  state: 'active',
);

final notificationInboxProvider =
    FutureProvider.family<NotificationInbox, NotificationQuery>((
      ref,
      query,
    ) async {
      ref.watch(sseServiceProvider.notifier);
      Timer? refreshTimer;
      final subscription = SseEventBus().eventStream.listen((event) {
        if (event.type != 'notification_updated') return;
        refreshTimer?.cancel();
        refreshTimer = Timer(
          const Duration(milliseconds: 250),
          ref.invalidateSelf,
        );
      });
      final webRefreshTimer = kIsWeb
          ? Timer(const Duration(seconds: 10), ref.invalidateSelf)
          : null;
      ref.onDispose(() {
        refreshTimer?.cancel();
        webRefreshTimer?.cancel();
        subscription.cancel();
      });

      final dio = ref.watch(apiClientProvider);
      final response = await dio.get(
        '/notifications',
        queryParameters: {
          'state': query.state,
          if (query.category != null) 'category': query.category,
          'limit': 100,
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
}

Future<void> markAllNotificationsRead(WidgetRef ref) async {
  await ref.read(apiClientProvider).post('/notifications/read-all');
  ref.invalidate(notificationInboxProvider);
}

Future<Map<String, dynamic>> generateNotificationDigest(WidgetRef ref) async {
  final response = await ref
      .read(apiClientProvider)
      .post('/notifications/digest');
  ref.invalidate(notificationInboxProvider);
  return Map<String, dynamic>.from(response.data as Map);
}
