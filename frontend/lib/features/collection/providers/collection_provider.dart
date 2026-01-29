import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../models/content.dart';
import 'collection_filter_provider.dart';

part 'collection_provider.g.dart';

@riverpod
class Collection extends _$Collection {
  @override
  FutureOr<ShareCardListResponse> build() async {
    final filter = ref.watch(collectionFilterProvider);
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
        if (tags != null && tags.isNotEmpty) 'tag': tags.join(','),
        if (platforms != null && platforms.isNotEmpty)
          'platform': platforms.join(','),
        if (statuses != null && statuses.isNotEmpty)
          'status': statuses.join(','),
        if (author != null) 'author': author,
        if (startDate != null) 'start_date': startDate.toIso8601String(),
        if (endDate != null) 'end_date': endDate.toIso8601String(),
        if (query != null) 'q': query,
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
