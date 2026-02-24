import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../network/api_client.dart';
import 'local_settings_provider.dart';

part 'system_status_provider.g.dart';

class SystemStatus {
  final bool needsSetup;
  final bool hasBot;
  final String version;
  final bool isLoaded;

  SystemStatus({
    this.needsSetup = false,
    this.hasBot = false,
    this.version = '',
    this.isLoaded = false,
  });
}

@riverpod
class SystemStatusNotifier extends _$SystemStatusNotifier {
  @override
  Future<SystemStatus> build() async {
    final settings = ref.watch(localSettingsProvider);
    if (settings.baseUrl.isEmpty) {
      return SystemStatus();
    }

    try {
      final dio = ref.read(apiClientProvider);
      final response = await dio.get('/init-status');
      if (response.statusCode == 200) {
        final data = response.data;
        return SystemStatus(
          needsSetup: data['needs_setup'] ?? false,
          hasBot: data['has_bot'] ?? false,
          version: data['version'] ?? '',
          isLoaded: true,
        );
      }
    } catch (_) {
      // 忽略错误，返回默认状态
    }
    return SystemStatus();
  }

  void refresh() {
    ref.invalidateSelf();
  }
}
