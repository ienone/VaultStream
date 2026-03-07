import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';
import '../models/discovery_models.dart';

part 'discovery_settings_provider.g.dart';

@riverpod
class DiscoverySettingsState extends _$DiscoverySettingsState {
  @override
  FutureOr<DiscoverySettings> build() async {
    final dio = ref.watch(apiClientProvider);
    final response = await dio.get('/api/v1/discovery/settings');
    return DiscoverySettings.fromJson(response.data);
  }

  Future<void> updateSettings({
    String? interestProfile,
    double? scoreThreshold,
    int? retentionDays,
  }) async {
    final dio = ref.read(apiClientProvider);
    final response = await dio.patch(
      '/api/v1/discovery/settings',
      data: {
        if (interestProfile != null) 'interest_profile': interestProfile,
        if (scoreThreshold != null) 'score_threshold': scoreThreshold,
        if (retentionDays != null) 'retention_days': retentionDays,
      },
    );
    state = AsyncData(DiscoverySettings.fromJson(response.data));
  }
}
