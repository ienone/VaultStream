import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../main.dart';
import '../config/env_config.dart';

part 'local_settings_provider.g.dart';

class LocalSettingsState {
  final String baseUrl;
  final String apiToken;

  LocalSettingsState({required this.baseUrl, required this.apiToken});

  LocalSettingsState copyWith({String? baseUrl, String? apiToken}) {
    return LocalSettingsState(
      baseUrl: baseUrl ?? this.baseUrl,
      apiToken: apiToken ?? this.apiToken,
    );
  }
}

@riverpod
class LocalSettings extends _$LocalSettings {
  static const _keyBaseUrl = 'api_base_url';
  static const _keyApiToken = 'api_token';

  @override
  LocalSettingsState build() {
    return LocalSettingsState(
      baseUrl: sharedPrefs.getString(_keyBaseUrl) ?? EnvConfig.baseUrl,
      apiToken: sharedPrefs.getString(_keyApiToken) ?? EnvConfig.apiToken,
    );
  }

  Future<void> setBaseUrl(String url) async {
    await sharedPrefs.setString(_keyBaseUrl, url);
    state = state.copyWith(baseUrl: url);
  }

  Future<void> setApiToken(String token) async {
    await sharedPrefs.setString(_keyApiToken, token);
    state = state.copyWith(apiToken: token);
  }

  Future<void> clearAuth() async {
    await sharedPrefs.remove(_keyApiToken);
    state = state.copyWith(apiToken: '');
  }

  Future<bool> testConnection(String baseUrl, String apiToken) async {
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          headers: {'X-API-Token': apiToken},
        ),
      );
      final response = await dio.get('/api/v1/dashboard/stats');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
