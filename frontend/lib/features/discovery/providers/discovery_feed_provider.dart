import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/api_client.dart';
import '../models/discovery_models.dart';

part 'discovery_feed_provider.g.dart';

enum DiscoveryFeedView { recent, later }

@riverpod
class DiscoveryFeed extends _$DiscoveryFeed {
  static const int _pageSize = 20;
  bool _isLoadingMore = false;
  int _queryVersion = 0;
  DiscoveryFeedView _view = DiscoveryFeedView.recent;

  DiscoveryFeedView get view => _view;

  @override
  FutureOr<DiscoveryItemListResponse> build() {
    _queryVersion += 1;
    _isLoadingMore = false;
    return _fetch(page: 1);
  }

  Future<DiscoveryItemListResponse> _fetch({required int page}) async {
    final dio = ref.read(apiClientProvider);
    final queryParameters = <String, dynamic>{
      'page': page,
      'size': _pageSize,
      'sort': 'published_at',
      'order': 'desc',
    };
    if (_view == DiscoveryFeedView.later) {
      queryParameters['state'] = 'snoozed';
    }
    final response = await dio.get(
      '/discovery/items',
      queryParameters: queryParameters,
    );
    return DiscoveryItemListResponse.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> showView(DiscoveryFeedView view) async {
    if (_view == view && state.hasValue) return;
    _view = view;
    await refresh();
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || _isLoadingMore) return;

    _isLoadingMore = true;
    final version = _queryVersion;
    try {
      final next = await _fetch(page: current.page + 1);
      if (!ref.mounted || version != _queryVersion) return;
      final items = state.value?.items ?? const <DiscoveryItem>[];
      final knownIds = items.map((item) => item.id).toSet();
      state = AsyncData(
        next.copyWith(
          items: [
            ...items,
            ...next.items.where((item) => knownIds.add(item.id)),
          ],
        ),
      );
    } finally {
      if (version == _queryVersion) _isLoadingMore = false;
    }
  }

  Future<void> actOnItem(int id, {required String stateValue}) async {
    final previous = state.value;
    if (previous == null) return;
    final index = previous.items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final version = _queryVersion;

    state = AsyncData(
      previous.copyWith(
        items: previous.items.where((item) => item.id != id).toList(),
        total: previous.total > 0 ? previous.total - 1 : 0,
      ),
    );

    try {
      final dio = ref.read(apiClientProvider);
      await dio.patch('/discovery/items/$id', data: {'state': stateValue});
    } catch (error, stackTrace) {
      final current = ref.mounted ? state.value : null;
      if (version == _queryVersion &&
          current != null &&
          !current.items.any((item) => item.id == id)) {
        final items = [...current.items];
        items.insert(index.clamp(0, items.length), previous.items[index]);
        state = AsyncData(
          current.copyWith(items: items, total: current.total + 1),
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> restoreItem(
    DiscoveryItem item, {
    String stateValue = 'visible',
  }) async {
    final version = _queryVersion;
    final dio = ref.read(apiClientProvider);
    await dio.patch('/discovery/items/${item.id}', data: {'state': stateValue});
    if (ref.mounted && version == _queryVersion) await refresh();
  }
}
