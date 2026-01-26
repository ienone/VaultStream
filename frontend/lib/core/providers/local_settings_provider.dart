import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    _initAsync();
    return LocalSettingsState(
      baseUrl: EnvConfig.baseUrl,
      apiToken: EnvConfig.apiToken,
    );
  }

  Future<void> _initAsync() async {
    final prefs = await SharedPreferences.getInstance();
    state = LocalSettingsState(
      baseUrl: prefs.getString(_keyBaseUrl) ?? EnvConfig.baseUrl,
      apiToken: prefs.getString(_keyApiToken) ?? EnvConfig.apiToken,
    );
  }

  Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBaseUrl, url);
    state = state.copyWith(baseUrl: url);
  }

  Future<void> setApiToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiToken, token);
    state = state.copyWith(apiToken: token);
  }
}
