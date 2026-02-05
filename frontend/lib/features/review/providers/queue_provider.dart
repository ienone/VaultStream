import 'package:flutter/foundation.dart';
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

  Future<void> reorderToIndex(int contentId, int index) async {
    final dio = ref.read(apiClientProvider);
    await dio.post(
      '/queue/items/$contentId/reorder',
      data: {'index': index},
    );
    // 不立即刷新，等待SSE事件或延迟软刷新
  }

  Future<void> softRefresh() async {
    // 后台更新数据，但不触发 UI 重建（仅当数据实际变化时才更新）
    final filter = ref.read(queueFilterProvider);
    try {
      final newData = await _fetchQueue(
        ruleId: filter.ruleId,
        status: filter.status,
      );
      
      // 仅当数据实际变化时才更新
      final currentState = state;
      if (currentState is AsyncData) {
        final oldItems = currentState.value?.items;
        if (oldItems != null) {
          final oldIds = oldItems.map((e) => e.contentId).toList();
          final newIds = newData.items.map((e) => e.contentId).toList();
          
          // 比较ID列表和顺序
          if (!_listsEqual(oldIds, newIds)) {
            state = AsyncValue.data(newData);
          }
        } else {
          state = AsyncValue.data(newData);
        }
      } else {
        state = AsyncValue.data(newData);
      }
    } catch (e) {
      // 软刷新失败不影响现有数据
      debugPrint('Soft refresh failed: $e');
    }
  }

  bool _listsEqual(List a, List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> batchPushNow(List<int> contentIds) async {
    final dio = ref.read(apiClientProvider);
    await dio.post(
      '/queue/batch-push-now',
      data: {'content_ids': contentIds},
    );
    _safeInvalidate();
  }

  Future<void> batchReschedule(List<int> contentIds, DateTime startTime, {int interval = 300}) async {
    final dio = ref.read(apiClientProvider);
    await dio.post(
      '/queue/batch-reschedule',
      data: {
        'content_ids': contentIds,
        'start_time': startTime.toUtc().toIso8601String(),
        'interval_seconds': interval,
      },
    );
    _safeInvalidate();
  }

  Future<void> updateSchedule(int contentId, DateTime scheduledAt) async {
    final dio = ref.read(apiClientProvider);
    await dio.post(
      '/queue/items/$contentId/schedule',
      data: {'scheduled_at': scheduledAt.toUtc().toIso8601String()},
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
