import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../models/discovery_models.dart';
import 'discovery_filter_provider.dart';

part 'discovery_items_provider.g.dart';

@riverpod
class DiscoveryItems extends _$DiscoveryItems {
  bool _isFetchingMore = false;

  @override
  FutureOr<DiscoveryItemListResponse> build() async {
    final filter = ref.watch(discoveryFilterProvider);

    return _fetch(
      page: 1,
      query: filter.searchQuery.isEmpty ? null : filter.searchQuery,
      state: filter.state,
      sourceKind: filter.sourceKind,
      scoreMin: filter.scoreMin,
      scoreMax: filter.scoreMax,
      tags: filter.tags.isNotEmpty ? filter.tags : null,
      sortBy: filter.sortBy,
      sortOrder: filter.sortOrder,
    );
  }

  Future<DiscoveryItemListResponse> _fetch({
    int page = 1,
    int size = 20,
    String? query,
    String? state,
    String? sourceKind,
    double? scoreMin,
    double? scoreMax,
    List<String>? tags,
    String sortBy = 'created_at',
    String sortOrder = 'desc',
  }) async {
    final dio = ref.watch(apiClientProvider);

    final response = await dio.get(
      '/discovery/items',
      queryParameters: {
        'page': page,
        'size': size,
        'sort': sortBy,
        'order': sortOrder,
        if (state != null) 'state': state,
        if (sourceKind != null) 'source_kind': sourceKind,
        if (scoreMin != null) 'score_min': scoreMin,
        if (scoreMax != null) 'score_max': scoreMax,
        if (tags case final tags? when tags.isNotEmpty) 'tag': tags.join(','),
        if (query != null) 'q': query,
      },
    );

    return DiscoveryItemListResponse.fromJson(response.data);
  }

  Future<void> fetchMore() async {
    if (_isFetchingMore || state.isLoading || state.isRefreshing || state.isReloading) {
      return;
    }

    final currentData = state.value;
    if (currentData == null || !currentData.hasMore) return;

    _isFetchingMore = true;

    try {
      final filter = ref.read(discoveryFilterProvider);
      final nextData = await _fetch(
        page: currentData.page + 1,
        query: filter.searchQuery.isEmpty ? null : filter.searchQuery,
        state: filter.state,
        sourceKind: filter.sourceKind,
        scoreMin: filter.scoreMin,
        scoreMax: filter.scoreMax,
        tags: filter.tags.isNotEmpty ? filter.tags : null,
        sortBy: filter.sortBy,
        sortOrder: filter.sortOrder,
      );

      state = AsyncData(
        nextData.copyWith(items: [...currentData.items, ...nextData.items]),
      );
    } catch (e, st) {
      debugPrint('DiscoveryItems.fetchMore failed: $e');
      debugPrintStack(stackTrace: st);
    } finally {
      _isFetchingMore = false;
    }
  }
}

@riverpod
Future<DiscoveryItem> discoveryItemDetail(Ref ref, int id) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/discovery/items/$id');
  return DiscoveryItem.fromJson(response.data);
}
