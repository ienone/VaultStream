import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/sse_service.dart';
import '../../search/search_models.dart';
import '../../search/search_provider.dart';
import '../models/content.dart';
import '../models/processing_status.dart';
import 'collection_filter_provider.dart';

part 'collection_provider.g.dart';

const _collectionEventTypes = {
  'content_created',
  'content_updated',
  'content_deleted',
};

@riverpod
class Collection extends _$Collection {
  UnifiedSearchRequest? _request;
  int _loadedPages = 1;
  int _generation = 0;

  @override
  Future<ShareCardListResponse> build() async {
    final request = ref.watch(collectionFilterProvider).toSearchRequest();
    _generation++;
    if (request != _request) _loadedPages = 1;
    _request = request;
    ref.watch(sseServiceProvider.notifier);
    Timer? refreshTimer;
    final subscription = SseEventBus().eventStream.listen((event) {
      if (!_collectionEventTypes.contains(event.type)) return;
      refreshTimer?.cancel();
      refreshTimer = Timer(
        const Duration(milliseconds: 300),
        ref.invalidateSelf,
      );
    });
    ref.onDispose(() {
      refreshTimer?.cancel();
      subscription.cancel();
    });

    // 后端拥有筛选和排序。实时刷新重读已加载页，不在客户端猜测归属，
    // 也不把阅读中的长列表缩回第一页。
    final pages = _loadedPages;
    final generation = _generation;
    var result = await _fetch(request);
    for (var page = 2; page <= pages && result.hasMore; page++) {
      if (!ref.mounted || generation != _generation) return result;
      final next = await _fetch(request.copyWith(page: page));
      result = next.copyWith(items: [...result.items, ...next.items]);
    }
    return result;
  }

  Future<ShareCardListResponse> _fetch(UnifiedSearchRequest request) async {
    final result = await fetchUnifiedSearch(
      ref.read(apiClientProvider),
      request,
    );
    return ShareCardListResponse(
      items: result.contents.map((hit) => hit.card).toList(growable: false),
      total: result.contentTotal,
      page: result.page,
      size: result.size,
      hasMore: result.contentHasMore,
    );
  }

  Future<void> fetchMore() async {
    if (state.isLoading) return;
    final current = state.value;
    if (current == null || !current.hasMore) return;
    final generation = _generation;
    final request = _request!.copyWith(page: current.page + 1);
    // ignore: invalid_use_of_internal_member
    state = const AsyncLoading<ShareCardListResponse>().copyWithPrevious(state);
    try {
      final next = await _fetch(request);
      if (!ref.mounted || generation != _generation) return;
      _loadedPages = next.page;
      state = AsyncData(
        next.copyWith(items: [...current.items, ...next.items]),
      );
    } catch (error, stack) {
      if (!ref.mounted || generation != _generation) return;
      final failure = AsyncError<ShareCardListResponse>(error, stack);
      // ignore: invalid_use_of_internal_member
      state = failure.copyWithPrevious(state);
    }
  }
}

@riverpod
Future<ContentDetail> contentDetail(Ref ref, int id) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/contents/$id');
  return ContentDetail.fromJson(response.data);
}

/// 后处理状态使用正式 contract，不推断后台任务是否完成。
@riverpod
Future<ContentProcessingStatus> contentProcessingStatus(Ref ref, int id) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/contents/$id/processing-status');
  return ContentProcessingStatus.fromJson(
    Map<String, dynamic>.from(response.data as Map),
  );
}
