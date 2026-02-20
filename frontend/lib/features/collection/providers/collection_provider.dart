import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/sse_service.dart';
import '../models/content.dart';
import 'collection_filter_provider.dart';

part 'collection_provider.g.dart';

/// 收藏库相关的 SSE 事件类型
const _collectionEventTypes = {
  'content_created',
  'content_updated',
  'content_deleted',
};

@riverpod
class Collection extends _$Collection {
  Timer? _debounceTimer;
  StreamSubscription? _sseSub;
  final List<SseEvent> _pendingEvents = [];
  bool _isDraining = false;

  @override
  FutureOr<ShareCardListResponse> build() async {
    final filter = ref.watch(collectionFilterProvider);

    // 启动 SSE 服务（确保服务已初始化）
    ref.watch(sseServiceProvider.notifier);

    // 监听 SSE 事件：先入队，再批量防抖处理，避免事件丢失
    _sseSub?.cancel();
    _sseSub = SseEventBus().eventStream.listen((event) {
      if (_collectionEventTypes.contains(event.type)) {
        _pendingEvents.add(event);
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 300), () {
          _drainPendingEvents();
        });
      }
    });

    ref.onDispose(() {
      _sseSub?.cancel();
      _debounceTimer?.cancel();
    });

    return _fetch(
      page: 1,
      query: filter.searchQuery.isEmpty ? null : filter.searchQuery,
      platforms: filter.platforms.isNotEmpty ? filter.platforms : null,
      statuses: filter.statuses.isNotEmpty ? filter.statuses : null,
      author: filter.author,
      startDate: filter.dateRange?.start,
      endDate: filter.dateRange?.end,
      tags: filter.tags.isNotEmpty ? filter.tags : null,
    );
  }

  Future<void> _drainPendingEvents() async {
    if (_isDraining) return;
    _isDraining = true;
    try {
      while (_pendingEvents.isNotEmpty) {
        final batch = List<SseEvent>.from(_pendingEvents);
        _pendingEvents.clear();

        bool needFullRefresh = false;

        // 同一 content 仅保留最后一条事件，减少重复处理
        final Map<int, SseEvent> latestById = {};
        for (final event in batch) {
          final id = _extractEventId(event);
          if (id == null) {
            needFullRefresh = true;
            continue;
          }
          latestById[id] = event;
        }

        for (final event in latestById.values) {
          final ok = await _applyIncrementalEvent(event);
          if (!ok) {
            needFullRefresh = true;
          }
        }

        if (needFullRefresh) {
          ref.invalidateSelf();
        }
      }
    } finally {
      _isDraining = false;
    }
  }

  int? _extractEventId(SseEvent event) {
    final raw = event.data['id'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  bool _canEvaluateFilterLocally(CollectionFilterState filter) {
    // status 与 q 在 /cards 事件增量场景下无法与后端完全等价判断，回退全量刷新更安全
    if (filter.statuses.isNotEmpty) return false;
    if (filter.searchQuery.trim().isNotEmpty) return false;
    return true;
  }

  bool _matchesLocalFilter(ShareCard card, CollectionFilterState filter) {
    if (filter.platforms.isNotEmpty) {
      final normalized = filter.platforms.map((e) => e.toLowerCase()).toSet();
      if (!normalized.contains(card.platform.toLowerCase())) {
        return false;
      }
    }

    if (filter.author != null && filter.author!.trim().isNotEmpty) {
      final keyword = filter.author!.trim().toLowerCase();
      final author = (card.authorName ?? '').toLowerCase();
      if (!author.contains(keyword)) {
        return false;
      }
    }

    if (filter.tags.isNotEmpty) {
      final cardTags = card.tags.map((e) => e.toLowerCase()).toSet();
      final hasAnyTag = filter.tags.any((tag) => cardTags.contains(tag.toLowerCase()));
      if (!hasAnyTag) {
        return false;
      }
    }

    if (filter.dateRange != null && card.createdAt != null) {
      final start = filter.dateRange!.start;
      final end = filter.dateRange!.end;
      final createdAt = card.createdAt!;
      if (createdAt.isBefore(start) || createdAt.isAfter(end)) {
        return false;
      }
    }

    return true;
  }

  Future<bool> _applyIncrementalEvent(SseEvent event) async {
    final current = state.value;
    if (current == null) return false;

    final id = _extractEventId(event);
    if (id == null) return false;

    if (event.type == 'content_deleted') {
      final updated = current.items.where((c) => c.id != id).toList();
      if (updated.length < current.items.length) {
        state = AsyncData(current.copyWith(
          items: updated,
          total: current.total > 0 ? current.total - 1 : 0,
        ));
      }
      return true;
    }

    if (event.type != 'content_created' && event.type != 'content_updated') {
      return false;
    }

    final filter = ref.read(collectionFilterProvider);
    if (!_canEvaluateFilterLocally(filter)) {
      return false;
    }

    try {
      final dio = ref.read(apiClientProvider);
      final resp = await dio.get('/cards/$id');
      final card = ShareCard.fromJson(resp.data);

      final refreshed = state.value;
      if (refreshed == null) return false;

      final items = [...refreshed.items];
      final idx = items.indexWhere((c) => c.id == id);
      final matches = _matchesLocalFilter(card, filter);

      if (matches) {
        if (idx == -1) {
          items.insert(0, card);
          state = AsyncData(refreshed.copyWith(
            items: items,
            total: refreshed.total + 1,
          ));
        } else {
          items[idx] = card;
          state = AsyncData(refreshed.copyWith(items: items));
        }
      } else {
        if (idx != -1) {
          items.removeAt(idx);
          state = AsyncData(refreshed.copyWith(
            items: items,
            total: refreshed.total > 0 ? refreshed.total - 1 : 0,
          ));
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<ShareCardListResponse> _fetch({
    int page = 1,
    int size = 20,
    List<String>? tags,
    List<String>? platforms,
    List<String>? statuses,
    String? author,
    DateTime? startDate,
    DateTime? endDate,
    String? query,
  }) async {
    final dio = ref.watch(apiClientProvider);

    final response = await dio.get(
      '/cards',
      queryParameters: {
        'page': page,
        'size': size,
        if (tags case final tags? when tags.isNotEmpty) 'tag': tags.join(','),
        if (platforms case final platforms? when platforms.isNotEmpty)
          'platform': platforms.join(','),
        if (statuses case final statuses? when statuses.isNotEmpty)
          'status': statuses.join(','),
        'author': ?author,
        if (startDate != null) 'start_date': startDate.toIso8601String(),
        if (endDate != null) 'end_date': endDate.toIso8601String(),
        'q': ?query,
      },
    );

    return ShareCardListResponse.fromJson(response.data);
  }

  Future<void> fetchMore() async {
    if (state.isLoading || state.isRefreshing || state.isReloading) return;

    final currentData = state.value;
    if (currentData == null || !currentData.hasMore) return;

    // ignore: invalid_use_of_internal_member
    state = const AsyncLoading<ShareCardListResponse>().copyWithPrevious(state);

    try {
      final filter = ref.read(collectionFilterProvider);
      final nextData = await _fetch(
        page: currentData.page + 1,
        query: filter.searchQuery.isEmpty ? null : filter.searchQuery,
        platforms: filter.platforms.isNotEmpty ? filter.platforms : null,
        statuses: filter.statuses.isNotEmpty ? filter.statuses : null,
        author: filter.author,
        startDate: filter.dateRange?.start,
        endDate: filter.dateRange?.end,
        tags: filter.tags.isNotEmpty ? filter.tags : null,
      );

      state = AsyncData(
        nextData.copyWith(items: [...currentData.items, ...nextData.items]),
      );
    } catch (e, st) {
      // ignore: invalid_use_of_internal_member
      state = AsyncError<ShareCardListResponse>(e, st).copyWithPrevious(state);
    }
  }
}

@riverpod
Future<ContentDetail> contentDetail(Ref ref, int id) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/contents/$id');
  return ContentDetail.fromJson(response.data);
}
