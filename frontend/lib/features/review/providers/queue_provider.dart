import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/sse_service.dart';
import '../models/queue_item.dart';

part 'queue_provider.g.dart';

// 队列配置常量
class _QueueConfig {
  // SSE 事件类型
  static const eventContentPushed = 'content_pushed';
  static const eventQueueUpdated = 'queue_updated';

  // 防抖延迟
  static const refreshDebounce = Duration(milliseconds: 500);
}

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

  const QueueFilterState({this.ruleId, this.status = QueueStatus.willPush});

  QueueFilterState copyWith({int? ruleId, QueueStatus? status}) {
    return QueueFilterState(
      ruleId: ruleId ?? this.ruleId,
      status: status ?? this.status,
    );
  }
}

@riverpod
class ContentQueue extends _$ContentQueue {
  StreamSubscription? _sseSub;
  Timer? _debounceTimer;

  @override
  FutureOr<QueueListResponse> build() async {
    final filter = ref.watch(queueFilterProvider);

    // 启动 SSE 服务
    ref.watch(sseServiceProvider.notifier);

    // 监听 SSE 事件自动刷新 - 直接订阅全局事件总线
    _sseSub?.cancel();
    _sseSub = SseEventBus().eventStream.listen(
      _handleSseEvent,
      onError: (_) {},
    );

    ref.onDispose(() {
      _sseSub?.cancel();
      _debounceTimer?.cancel();
    });

    return _fetchQueue(ruleId: filter.ruleId, status: filter.status);
  }

  void _handleSseEvent(SseEvent event) {
    // 使用常量匹配事件类型
    if (event.type == _QueueConfig.eventContentPushed ||
        event.type == _QueueConfig.eventQueueUpdated) {
      // 防抖刷新：避免短时间内多次事件触发多次请求
      _debounceTimer?.cancel();
      _debounceTimer = Timer(_QueueConfig.refreshDebounce, () {
        softRefresh();
        // 同时刷新统计数字
        final filter = ref.read(queueFilterProvider);
        ref.invalidate(queueStatsProvider(filter.ruleId));
      });
    }
  }

  Future<QueueListResponse> _fetchQueue({
    int? ruleId,
    QueueStatus? status,
  }) async {
    final dio = ref.read(apiClientProvider);
    final response = await dio.get(
      '/distribution-queue/items',
      queryParameters: {
        'rule_id': ?ruleId,
        if (status case final status?) 'status': status.value,
      },
    );
    return QueueListResponse.fromJson(response.data);
  }

  Future<void> moveToStatus(
    int contentId,
    QueueStatus newStatus, {
    String? reason,
  }) async {
    final dio = ref.read(apiClientProvider);
    await dio.post(
      '/distribution-queue/content/$contentId/status',
      data: {'status': newStatus.value, 'reason': ?reason},
    );
    _safeInvalidate();

    // Refresh stats
    final filter = ref.read(queueFilterProvider);
    ref.invalidate(queueStatsProvider(filter.ruleId));
  }

  Future<void> reorderToIndex(int contentId, int index) async {
    final dio = ref.read(apiClientProvider);
    await dio.post(
      '/distribution-queue/content/$contentId/reorder',
      data: {'index': index},
    );
    // 不立即刷新，等待SSE事件或延迟软刷新
  }

  Future<void> softRefresh() async {
    // 后台更新数据，仅当数据实际变化时才更新
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
          final newItems = newData.items;

          // 比较 ID 列表、顺序和总数
          final needsUpdate = _shouldUpdate(oldItems, newItems, newData);

          if (needsUpdate) {
            state = AsyncValue.data(newData);
          }
        } else {
          state = AsyncValue.data(newData);
        }
      } else {
        state = AsyncValue.data(newData);
      }
    } catch (_) {
      // 软刷新失败不影响现有数据
    }
  }

  bool _shouldUpdate(
    List<QueueItem> oldItems,
    List<QueueItem> newItems,
    QueueListResponse newData,
  ) {
    // 检查是否需要更新
    if (oldItems.length != newItems.length) return true;

    // 检查 ID 顺序
    for (int i = 0; i < oldItems.length; i++) {
      if (oldItems[i].contentId != newItems[i].contentId) return true;
      // 检查计划时间是否变化
      if (oldItems[i].scheduledTime != newItems[i].scheduledTime) return true;
      // 检查状态与错误信息是否变化
      if (oldItems[i].status != newItems[i].status) return true;
      if (oldItems[i].reason != newItems[i].reason) return true;
      if (oldItems[i].priority != newItems[i].priority) return true;
    }

    return false;
  }

  Future<void> batchPushNow(List<int> contentIds) async {
    final dio = ref.read(apiClientProvider);
    await dio.post(
      '/distribution-queue/content/batch-push-now',
      data: {'content_ids': contentIds},
    );
    _safeInvalidate();
    // 刷新统计
    final filter = ref.read(queueFilterProvider);
    ref.invalidate(queueStatsProvider(filter.ruleId));
  }

  Future<void> batchReschedule(
    List<int> contentIds,
    DateTime startTime, {
    int interval = 300,
  }) async {
    final dio = ref.read(apiClientProvider);
    await dio.post(
      '/distribution-queue/content/batch-reschedule',
      data: {
        'content_ids': contentIds,
        'start_time': startTime.toUtc().toIso8601String(),
        'interval_seconds': interval,
      },
    );
    _safeInvalidate();
    // 刷新统计
    final filter = ref.read(queueFilterProvider);
    ref.invalidate(queueStatsProvider(filter.ruleId));
  }

  Future<void> pushNow(int contentId) async {
    final dio = ref.read(apiClientProvider);
    await dio.post('/distribution-queue/content/$contentId/push-now');
    _safeInvalidate();
    final filter = ref.read(queueFilterProvider);
    ref.invalidate(queueStatsProvider(filter.ruleId));
  }

  Future<void> mergeGroup(List<int> contentIds, {DateTime? scheduledAt}) async {
    final dio = ref.read(apiClientProvider);
    await dio.post(
      '/distribution-queue/content/merge-group',
      data: {
        'content_ids': contentIds,
        if (scheduledAt case final scheduledAt?)
          'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      },
    );
    _safeInvalidate();
    final filter = ref.read(queueFilterProvider);
    ref.invalidate(queueStatsProvider(filter.ruleId));
  }

  Future<void> updateSchedule(int contentId, DateTime scheduledAt) async {
    final dio = ref.read(apiClientProvider);
    await dio.post(
      '/distribution-queue/content/$contentId/schedule',
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
    '/distribution-queue/stats',
    queryParameters: {
      if (ruleId != null) 'rule_id': ruleId,
    },
  );
  final data = Map<String, dynamic>.from(response.data as Map);

  final mapped = <String, int>{
    'will_push': (data['will_push'] ?? 0),
    'filtered': (data['filtered'] ?? 0),
    'pending_review': (data['pending_review'] ?? 0),
    'pushed': (data['pushed'] ?? 0),
    'total': (data['total'] ?? 0),
  };
  return mapped;
}
