import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../models/discovery_models.dart';

part 'discovery_sources_provider.g.dart';

@riverpod
class DiscoverySources extends _$DiscoverySources {
  @override
  FutureOr<List<DiscoverySource>> build() async {
    final dio = ref.watch(apiClientProvider);
    final response = await dio.get('/discovery/sources');
    final list = (response.data as List)
        .map((e) => DiscoverySource.fromJson(e))
        .toList();
    return list;
  }

  Future<void> createSource(DiscoverySource source) async {
    final dio = ref.read(apiClientProvider);
    await dio.post('/discovery/sources', data: {
      'kind': source.kind,
      'name': source.name,
      'enabled': source.enabled,
      'config': source.config,
      'sync_interval_minutes': source.syncIntervalMinutes,
    });
    ref.invalidateSelf();
  }

  Future<void> updateSource(int id, {
    String? name,
    bool? enabled,
    Map<String, dynamic>? config,
    int? syncIntervalMinutes,
  }) async {
    final dio = ref.read(apiClientProvider);
    await dio.put('/discovery/sources/$id', data: {
      if (name != null) 'name': name,
      if (enabled != null) 'enabled': enabled,
      if (config != null) 'config': config,
      if (syncIntervalMinutes != null) 'sync_interval_minutes': syncIntervalMinutes,
    });
    ref.invalidateSelf();
  }

  Future<void> deleteSource(int id) async {
    final dio = ref.read(apiClientProvider);
    await dio.delete('/discovery/sources/$id');
    ref.invalidateSelf();
  }

  Future<void> triggerSync(int id) async {
    final dio = ref.read(apiClientProvider);
    await dio.post('/discovery/sources/$id/sync');
  }
}
