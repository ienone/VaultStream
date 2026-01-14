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
