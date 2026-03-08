import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import 'discovery_items_provider.dart';

part 'discovery_actions_provider.g.dart';

@riverpod
class DiscoveryActions extends _$DiscoveryActions {
  bool _isDisposed = false;

  @override
  bool build() {
    ref.keepAlive();
    _isDisposed = false;
    ref.onDispose(() {
      _isDisposed = true;
    });
    return false;
  }

  Future<void> promoteItem(int id) => _runAction(
    (dio) => dio.patch('/discovery/items/$id', data: {'state': 'promoted'}),
  );

  Future<void> ignoreItem(int id) => _runAction(
    (dio) => dio.patch('/discovery/items/$id', data: {'state': 'ignored'}),
  );

  Future<void> bulkAction(Set<int> ids, String action) async {
    if (ids.isEmpty) return;
    await _runAction(
      (dio) => dio.post('/discovery/items/bulk-action', data: {
        'ids': ids.toList(),
        'action': action,
      }),
    );
  }

  Future<void> _runAction(Future<void> Function(Dio dio) request) async {
    if (_isDisposed) return;

    state = true;
    try {
      final dio = ref.read(apiClientProvider);
      await request(dio);
      if (_isDisposed) return;
      ref.invalidate(discoveryItemsProvider);
    } finally {
      if (!_isDisposed) {
        state = false;
      }
    }
  }
}
