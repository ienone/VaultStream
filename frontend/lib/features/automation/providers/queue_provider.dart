import 'dart:async';

import 'package:dio/dio.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/sse_service.dart';
import '../models/queue_item.dart';

part 'queue_provider.g.dart';

typedef QueueFilter = ({int? ruleId, QueueStatus status});

typedef QueueSendResult = ({int id, bool sent, String? error});

Future<List<QueueSendResult>> sendQueueItems(Dio api, List<int> ids) async {
  if (ids.isEmpty) return [];
  final response = await api.post<Map<String, dynamic>>(
    '/distribution-queue/items/batch-push-now',
    data: {'item_ids': ids},
    options: Options(receiveTimeout: Duration.zero),
  );
  return (response.data!['items'] as List).map((raw) {
    final item = raw as Map<String, dynamic>;
    return (
      id: item['item_id'] as int,
      sent: item['sent'] as bool,
      error: item['error'] as String?,
    );
  }).toList();
}

@riverpod
class ContentQueue extends _$ContentQueue {
  StreamSubscription? _sseSub;
  Timer? _debounceTimer;

  @override
  FutureOr<QueueListResponse> build(QueueFilter filter) async {
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
    if (event.type == 'reconnected' || event.type == 'queue_updated') {
      // 防抖刷新：避免短时间内多次事件触发多次请求
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        softRefresh();
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

  Future<void> cancelItems(List<int> ids) async {
    await ref
        .read(apiClientProvider)
        .post('/distribution-queue/cancel', data: {'item_ids': ids});
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore) return;
    final next = await _fetchQueue(
      ruleId: filter.ruleId,
      status: filter.status,
      page: current.page + 1,
    );
    if (!ref.mounted) {
      return;
    }
    final items = {
      for (final item in current.items) item.id: item,
      for (final item in next.items) item.id: item,
    };
    state = AsyncData(next.copyWith(items: items.values.toList()));
  }

  Future<void> softRefresh() async {
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
      if (!ref.mounted) {
        return;
      }
      state = AsyncData(latest!.copyWith(items: items));
    } catch (_) {
      // Keep the readable list until the next event or explicit refresh.
    }
  }

  Future<void> schedule(List<int> ids, DateTime at) async {
    await ref
        .read(apiClientProvider)
        .post(
          '/distribution-queue/items/batch-schedule',
          data: {'item_ids': ids, 'start_time': at.toUtc().toIso8601String()},
        );
  }
}
