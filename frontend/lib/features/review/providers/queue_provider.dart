import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../models/queue_item.dart';

part 'queue_provider.g.dart';

@riverpod
class QueueFilter extends _$QueueFilter {
  @override
  QueueFilterState build() => const QueueFilterState();

  void setRuleId(int? ruleId) {
    state = state.copyWith(ruleId: ruleId);
  }

  void setStatus(QueueStatus status) {
    state = state.copyWith(status: status);
  }
}

class QueueFilterState {
  final int? ruleId;
  final QueueStatus status;

  const QueueFilterState({
    this.ruleId,
    this.status = QueueStatus.willPush,
  });

  QueueFilterState copyWith({
    int? ruleId,
    QueueStatus? status,
  }) {
    return QueueFilterState(
      ruleId: ruleId ?? this.ruleId,
      status: status ?? this.status,
    );
  }
}

@riverpod
class ContentQueue extends _$ContentQueue {
  @override
  FutureOr<QueueListResponse> build() async {
    final filter = ref.watch(queueFilterProvider);
    return _fetchQueue(ruleId: filter.ruleId, status: filter.status);
  }

  Future<QueueListResponse> _fetchQueue({
    int? ruleId,
    QueueStatus? status,
  }) async {
    final dio = ref.read(apiClientProvider);
    final response = await dio.get(
      '/queue/items',
      queryParameters: {
        if (ruleId != null) 'rule_id': ruleId,
        if (status != null) 'status': status.value,
      },
    );
    return QueueListResponse.fromJson(response.data);
  }

  Future<void> moveToStatus(int contentId, QueueStatus newStatus, {String? reason}) async {
    final dio = ref.read(apiClientProvider);
    await dio.post(
      '/queue/items/$contentId/move',
      data: {
        'status': newStatus.value,
        if (reason != null) 'reason': reason,
      },
    );
    _safeInvalidate();
    
    // Refresh stats
    final filter = ref.read(queueFilterProvider);
    ref.invalidate(queueStatsProvider(filter.ruleId));
  }

  Future<void> reorderItem(int contentId, int newPriority) async {
    final dio = ref.read(apiClientProvider);
    await dio.post(
      '/queue/items/$contentId/reorder',
      data: {'priority': newPriority},
    );
    _safeInvalidate();
  }

  Future<void> approveItem(int contentId) async {
    await moveToStatus(contentId, QueueStatus.willPush);
  }

  Future<void> rejectItem(int contentId, {String? reason}) async {
    await moveToStatus(contentId, QueueStatus.filtered, reason: reason);
  }

  Future<void> restoreToPending(int contentId) async {
    await moveToStatus(contentId, QueueStatus.willPush);
  }

  void _safeInvalidate() {
    try {
      ref.invalidateSelf();
    } catch (_) {}
  }

  void refresh() {
    _safeInvalidate();
  }
}

@riverpod
Future<Map<String, int>> queueStats(Ref ref, int? ruleId) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get(
    '/queue/stats',
    queryParameters: {
      if (ruleId != null) 'rule_id': ruleId,
    },
  );
  return Map<String, int>.from(response.data);
}
