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

  void setFilter({int? ruleId, required QueueStatus status}) {
    if (state.ruleId == ruleId && state.status == status) return;
    state = QueueFilterState(ruleId: ruleId, status: status);
  }

  void setRuleId(int? ruleId) {
    state = QueueFilterState(ruleId: ruleId, status: state.status);
  }

  void setStatus(QueueStatus status) {
    state = QueueFilterState(ruleId: state.ruleId, status: status);
  }
}

class QueueFilterState {
  final int? ruleId;
  final QueueStatus status;

  const QueueFilterState({this.ruleId, this.status = QueueStatus.willPush});
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
    int page = 1,
  }) async {
    final dio = ref.read(apiClientProvider);
    final response = await dio.get(
      '/distribution-queue/items',
      queryParameters: {
        'rule_id': ?ruleId,
        'page': page,
        if (status case final status?) 'status': status.value,
      },
    );
    return QueueListResponse.fromJson(response.data);
  }

  Future<void> moveToStatus(
    int itemId,
    QueueStatus newStatus, {
    String? reason,
  }) async {
    final dio = ref.read(apiClientProvider);
    await dio.post(
      '/distribution-queue/items/$itemId/status',
      data: {'status': newStatus.value, 'reason': ?reason},
    );
    _safeInvalidate();

    // Refresh stats
    final filter = ref.read(queueFilterProvider);
    ref.invalidate(queueStatsProvider(filter.ruleId));
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore) return;
    final filter = ref.read(queueFilterProvider);
    final next = await _fetchQueue(
      ruleId: filter.ruleId,
      status: filter.status,
      page: current.page + 1,
    );
    if (!ref.mounted || !identical(filter, ref.read(queueFilterProvider))) {
      return;
    }
    final items = {
      for (final item in current.items) item.id: item,
      for (final item in next.items) item.id: item,
    };
    state = AsyncData(next.copyWith(items: items.values.toList()));
  }

  Future<void> softRefresh() async {
    final filter = ref.read(queueFilterProvider);
    final pages = state.value?.page ?? 1;
    try {
      final items = <QueueItem>[];
      QueueListResponse? latest;
      for (var page = 1; page <= pages; page++) {
        latest = await _fetchQueue(
          ruleId: filter.ruleId,
          status: filter.status,
          page: page,
        );
        items.addAll(latest.items);
        if (!latest.hasMore) break;
      }
      if (!ref.mounted || !identical(filter, ref.read(queueFilterProvider))) {
        return;
      }
      state = AsyncData(latest!.copyWith(items: items));
    } catch (_) {
      // Keep the readable list until the next event or explicit refresh.
    }
  }

  Future<QueueItem> loadItem(int itemId) async {
    final response = await ref
        .read(apiClientProvider)
        .get('/distribution-queue/items/$itemId');
    return QueueItem.fromJson(response.data as Map<String, dynamic>);
  }

  Future<QueueItem> pushNow(int itemId) async {
    final dio = ref.read(apiClientProvider);
    final response = await dio.post(
      '/distribution-queue/items/$itemId/push-now',
    );
    _safeInvalidate();
    final filter = ref.read(queueFilterProvider);
    ref.invalidate(queueStatsProvider(filter.ruleId));
    return QueueItem.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> updateSchedule(int itemId, DateTime scheduledAt) async {
    final dio = ref.read(apiClientProvider);
    await dio.post(
      '/distribution-queue/items/$itemId/schedule',
      data: {'scheduled_at': scheduledAt.toUtc().toIso8601String()},
    );
    _safeInvalidate();
  }

  void _safeInvalidate() {
    if (ref.mounted) ref.invalidateSelf();
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
    queryParameters: {'rule_id': ?ruleId},
  );
  final data = Map<String, dynamic>.from(response.data as Map);

  final mapped = <String, int>{
    'will_push': data['will_push'] as int,
    'filtered': data['filtered'] as int,
    'pushed': data['pushed'] as int,
    'total': data['total'] as int,
  };
  return mapped;
}
