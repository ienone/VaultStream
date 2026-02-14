// ignore_for_file: use_null_aware_elements

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../models/target_list_response.dart';
import '../models/render_config_preset.dart';

part 'targets_provider.g.dart';

@riverpod
class Targets extends _$Targets {
  @override
  FutureOr<TargetListResponse> build({String? platform, bool? enabled}) async {
    return _fetchTargets(platform: platform, enabled: enabled);
  }

  Future<TargetListResponse> _fetchTargets({
    String? platform,
    bool? enabled,
  }) async {
    final dio = ref.watch(apiClientProvider);
    final response = await dio.get(
      '/targets',
      queryParameters: {
        if (platform case final platform?) 'platform': platform,
        if (enabled case final enabled?) 'enabled': enabled,
      },
    );
    return TargetListResponse.fromJson(response.data);
  }

  Future<Map<String, dynamic>> testConnection({
    required String platform,
    required String targetId,
  }) async {
    final dio = ref.watch(apiClientProvider);
    final response = await dio.post(
      '/targets/test',
      data: {'platform': platform, 'target_id': targetId},
    );
    return response.data;
  }

  Future<void> batchUpdate({
    required List<int> ruleIds,
    required String targetPlatform,
    required String targetId,
    bool? enabled,
    bool? mergeForward,
    Map<String, dynamic>? renderConfig,
  }) async {
    final dio = ref.watch(apiClientProvider);
    await dio.post(
      '/targets/batch-update',
      data: {
        'rule_ids': ruleIds,
        'target_platform': targetPlatform,
        'target_id': targetId,
        if (enabled case final enabled?) 'enabled': enabled,
        if (mergeForward case final mergeForward?)
          'merge_forward': mergeForward,
        if (renderConfig case final renderConfig?)
          'render_config': renderConfig,
      },
    );
    ref.invalidateSelf();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

@riverpod
class RenderConfigPresets extends _$RenderConfigPresets {
  @override
  FutureOr<List<RenderConfigPreset>> build() async {
    return _fetchPresets();
  }

  Future<List<RenderConfigPreset>> _fetchPresets() async {
    final dio = ref.watch(apiClientProvider);
    final response = await dio.get('/render-config-presets');
    return (response.data as List)
        .map((e) => RenderConfigPreset.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RenderConfigPreset> getPreset(String id) async {
    final dio = ref.watch(apiClientProvider);
    final response = await dio.get('/render-config-presets/$id');
    return RenderConfigPreset.fromJson(response.data);
  }
}
