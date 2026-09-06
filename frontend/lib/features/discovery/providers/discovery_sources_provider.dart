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
    await dio.post(
      '/discovery/sources',
      data: {
        'kind': source.kind,
        'name': source.name,
        'enabled': source.enabled,
        'config': source.config,
        'sync_interval_minutes': source.syncIntervalMinutes,
      },
    );
    ref.invalidateSelf();
  }

  Future<void> updateSource(
    int id, {
    String? name,
    bool? enabled,
    Map<String, dynamic>? config,
    int? syncIntervalMinutes,
  }) async {
    final dio = ref.read(apiClientProvider);
    await dio.put(
      '/discovery/sources/$id',
      data: {
        'name': ?name,
        'enabled': ?enabled,
        'config': ?config,
        'sync_interval_minutes': ?syncIntervalMinutes,
      },
    );
    ref.invalidateSelf();
  }

  Future<void> deleteSource(int id) async {
    final dio = ref.read(apiClientProvider);
    await dio.delete('/discovery/sources/$id');
    ref.invalidateSelf();
  }

  Future<String?> triggerSync(int id, {bool force = false}) async {
    final dio = ref.read(apiClientProvider);
    final response = await dio.post(
      '/discovery/sources/$id/sync',
      queryParameters: force ? {'force': true} : null,
    );
    final data = response.data;
    if (data is Map && data['run_id'] != null) {
      return data['run_id'].toString();
    }
    return null;
  }

  Future<DiscoverySourceTestResult> testQuality(int id) async {
    final dio = ref.read(apiClientProvider);
    final response = await dio.post('/discovery/sources/$id/test');
    return DiscoverySourceTestResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }
}

class DiscoverySourceTestResult {
  const DiscoverySourceTestResult({
    required this.runId,
    required this.ok,
    required this.status,
    required this.sourceId,
    required this.sourceName,
    required this.sourceKind,
    required this.elapsedMs,
    this.itemCount,
    this.sampleCount,
    this.cursorAvailable,
    this.error,
  });

  factory DiscoverySourceTestResult.fromJson(Map<String, dynamic> json) {
    return DiscoverySourceTestResult(
      runId: json['run_id'] as String,
      ok: json['ok'] as bool,
      status: json['status'] as String,
      sourceId: (json['source_id'] as num).toInt(),
      sourceName: json['source_name'] as String,
      sourceKind: json['source_kind'] as String,
      elapsedMs: (json['elapsed_ms'] as num).toDouble(),
      itemCount: (json['item_count'] as num?)?.toInt(),
      sampleCount: (json['sample_count'] as num?)?.toInt(),
      cursorAvailable: json['cursor_available'] as bool?,
      error: json['error'] as String?,
    );
  }

  final String runId;
  final bool ok;
  final String status;
  final int sourceId;
  final String sourceName;
  final String sourceKind;
  final double elapsedMs;
  final int? itemCount;
  final int? sampleCount;
  final bool? cursorAvailable;
  final String? error;
}
