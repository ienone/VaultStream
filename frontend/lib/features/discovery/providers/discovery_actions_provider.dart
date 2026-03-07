import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import 'discovery_items_provider.dart';

part 'discovery_actions_provider.g.dart';

@riverpod
class DiscoveryActions extends _$DiscoveryActions {
  @override
  bool build() => false;

  Future<void> promoteItem(int id) async {
    state = true;
    try {
      final dio = ref.read(apiClientProvider);
      await dio.patch('/api/v1/discovery/items/$id', data: {'state': 'promoted'});
      ref.invalidate(discoveryItemsProvider);
    } finally {
      state = false;
    }
  }

  Future<void> ignoreItem(int id) async {
    state = true;
    try {
      final dio = ref.read(apiClientProvider);
      await dio.patch('/api/v1/discovery/items/$id', data: {'state': 'ignored'});
      ref.invalidate(discoveryItemsProvider);
    } finally {
      state = false;
    }
  }

  Future<void> bulkAction(Set<int> ids, String action) async {
    if (ids.isEmpty) return;
    state = true;
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post('/api/v1/discovery/items/bulk-action', data: {
        'ids': ids.toList(),
        'action': action,
      });
      ref.invalidate(discoveryItemsProvider);
    } finally {
      state = false;
    }
  }
}
