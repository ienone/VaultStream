class NotificationInbox {
  const NotificationInbox({
    required this.items,
    required this.total,
    required this.unreadCount,
  });

  factory NotificationInbox.fromJson(Map<String, dynamic> json) {
    return NotificationInbox(
      items: (json['items'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(NotificationInboxItem.fromJson)
          .toList(growable: false),
      total: (json['total'] as num?)?.toInt() ?? 0,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
    );
  }

  final List<NotificationInboxItem> items;
  final int total;
  final int unreadCount;
}

class NotificationInboxItem {
  const NotificationInboxItem({
    required this.id,
    required this.category,
    required this.severity,
    required this.title,
    required this.sourceType,
    required this.occurrenceCount,
    required this.firstOccurredAt,
    required this.lastOccurredAt,
    required this.isUnread,
    this.body,
    this.route,
    this.sourceId,
    this.payload = const {},
    this.readAt,
    this.mutedAt,
    this.snoozedUntil,
    this.expiresAt,
    this.dismissedAt,
  });

  factory NotificationInboxItem.fromJson(Map<String, dynamic> json) {
    return NotificationInboxItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      category: json['category']?.toString() ?? 'system',
      severity: json['severity']?.toString() ?? 'info',
      title: json['title']?.toString() ?? '系统消息',
      body: json['body']?.toString(),
      route: json['route']?.toString(),
      sourceType: json['source_type']?.toString() ?? 'system',
      sourceId: json['source_id']?.toString(),
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
      occurrenceCount: (json['occurrence_count'] as num?)?.toInt() ?? 1,
      firstOccurredAt: _date(json['first_occurred_at']) ?? DateTime.now(),
      lastOccurredAt: _date(json['last_occurred_at']) ?? DateTime.now(),
      readAt: _date(json['read_at']),
      mutedAt: _date(json['muted_at']),
      snoozedUntil: _date(json['snoozed_until']),
      expiresAt: _date(json['expires_at']),
      dismissedAt: _date(json['dismissed_at']),
      isUnread: json['is_unread'] == true,
    );
  }

  final int id;
  final String category;
  final String severity;
  final String title;
  final String? body;
  final String? route;
  final String sourceType;
  final String? sourceId;
  final Map<String, dynamic> payload;
  final int occurrenceCount;
  final DateTime firstOccurredAt;
  final DateTime lastOccurredAt;
  final DateTime? readAt;
  final DateTime? mutedAt;
  final DateTime? snoozedUntil;
  final DateTime? expiresAt;
  final DateTime? dismissedAt;
  final bool isUnread;

  bool get isMuted => mutedAt != null;
  bool get isSnoozed =>
      snoozedUntil != null && snoozedUntil!.isAfter(DateTime.now());
}

DateTime? _date(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
