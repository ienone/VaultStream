import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../models/system_setting.dart';

part 'settings_provider.g.dart';

@riverpod
class SystemSettings extends _$SystemSettings {
  @override
  FutureOr<List<SystemSetting>> build() async {
    final response = await ref.read(apiClientProvider).get('/settings');
    final List<dynamic> data = response.data;
    return data.map((json) => SystemSetting.fromJson(json)).toList();
  }

  Future<void> updateSetting(
    String key,
    dynamic value, {
    String? category,
    String? description,
  }) async {
    await ref
        .read(apiClientProvider)
        .put(
          '/settings/$key',
          data: {'value': value, 'description': description},
          queryParameters: category != null ? {'category': category} : null,
        );
    ref.invalidateSelf();
  }

  Future<void> deleteSetting(String key) async {
    await ref.read(apiClientProvider).delete('/settings/$key');
    ref.invalidateSelf();
  }
}

final semanticIndexStatusProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      final response = await ref
          .read(apiClientProvider)
          .get('/search/semantic/index-status');
      return Map<String, dynamic>.from(response.data as Map);
    });

final aiCapabilitiesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final response = await ref
          .read(apiClientProvider)
          .get('/ai/capabilities');
      final data = Map<String, dynamic>.from(response.data as Map);
      return (data['capabilities'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    });

final aiConnectivityTestProvider = Provider<AiConnectivityTestActions>((ref) {
  return AiConnectivityTestActions(ref);
});

final semanticIndexActionsProvider = Provider<SemanticIndexActions>((ref) {
  return SemanticIndexActions(ref);
});

final aiModelDiscoveryActionsProvider = Provider<AiModelDiscoveryActions>((
  ref,
) {
  return AiModelDiscoveryActions(ref);
});

class SemanticReindexResult {
  const SemanticReindexResult({this.runId});

  final String? runId;
}

/// 语义索引写操作边界。
///
/// Widget 只消费 typed result，不解析动作接口的动态响应。
class SemanticIndexActions {
  const SemanticIndexActions(this.ref);

  final Ref ref;

  Future<SemanticReindexResult> retryFailed({int limit = 100}) async {
    final response = await ref
        .read(apiClientProvider)
        .post(
          '/search/semantic/reindex',
          data: {'scope': 'failed', 'limit': limit},
        );
    final data = response.data;
    final rawRunId = data is Map ? data['run_id']?.toString().trim() : null;
    ref.invalidate(semanticIndexStatusProvider);
    return SemanticReindexResult(
      runId: rawRunId == null || rawRunId.isEmpty ? null : rawRunId,
    );
  }
}

class AiModelDiscoveryActions {
  const AiModelDiscoveryActions(this.ref);

  final Ref ref;

  Future<List<String>> discover(String target) async {
    final response = await ref
        .read(apiClientProvider)
        .post('/ai/models', data: {'target': target});
    final data = Map<String, dynamic>.from(response.data as Map);
    return (data['models'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toList();
  }
}

class AiConnectivityTestActions {
  const AiConnectivityTestActions(this.ref);

  final Ref ref;

  Future<AiConnectivityTestResult> run(String target) async {
    final response = await ref
        .read(apiClientProvider)
        .post('/ai/connectivity-test', data: {'target': target});
    ref.invalidate(aiCapabilitiesProvider);
    return AiConnectivityTestResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }
}

class AiConnectivityTestResult {
  const AiConnectivityTestResult({
    required this.runId,
    required this.target,
    required this.status,
    required this.ok,
    required this.elapsedMs,
    this.error,
  });

  factory AiConnectivityTestResult.fromJson(Map<String, dynamic> json) {
    return AiConnectivityTestResult(
      runId: json['run_id'] as String,
      target: json['target'] as String,
      status: json['status'] as String,
      ok: json['ok'] as bool,
      elapsedMs: (json['elapsed_ms'] as num).toDouble(),
      error: json['error'] as String?,
    );
  }

  final String runId;
  final String target;
  final String status;
  final bool ok;
  final double elapsedMs;
  final String? error;
}
