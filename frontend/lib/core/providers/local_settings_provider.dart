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

  @override
  LocalSettingsState build() {
    if (!isSharedPrefsInitialized) {
      return LocalSettingsState(
        baseUrl: EnvConfig.baseUrl,
        apiToken: EnvConfig.apiToken,
      );
    }

    return LocalSettingsState(
      baseUrl: sharedPrefs.getString(_keyBaseUrl) ?? EnvConfig.baseUrl,
      apiToken: initialApiToken ?? EnvConfig.apiToken,
    );
  }

  Future<void> setBaseUrl(String url) async {
    if (isSharedPrefsInitialized) {
      await sharedPrefs.setString(_keyBaseUrl, url);
    }
    state = state.copyWith(baseUrl: url);
  }

  Future<void> setApiToken(String token) async {
    if (isSecureStorageInitialized) {
      await secureStorage.write(key: apiTokenStorageKey, value: token);
    }
    if (isSharedPrefsInitialized) {
      await sharedPrefs.remove(apiTokenStorageKey);
    }
    initialApiToken = token;
    state = state.copyWith(apiToken: token);
  }

  Future<void> clearAuth() async {
    if (isSecureStorageInitialized) {
      await secureStorage.delete(key: apiTokenStorageKey);
    }
    if (isSharedPrefsInitialized) {
      await sharedPrefs.remove(apiTokenStorageKey);
    }
    initialApiToken = null;
    state = state.copyWith(apiToken: '');
  }

  Future<void> setConnection(String url, String token) async {
    if (isSecureStorageInitialized) {
      await secureStorage.write(key: apiTokenStorageKey, value: token);
    }
    if (isSharedPrefsInitialized) {
      await sharedPrefs.setString(_keyBaseUrl, url);
      await sharedPrefs.remove(apiTokenStorageKey);
    }
    initialApiToken = token;
    state = LocalSettingsState(baseUrl: url, apiToken: token);
  }

  Future<Map<String, dynamic>> validateConnection(
    String baseUrl,
    String apiToken,
  ) async {
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {'X-API-Token': apiToken},
          followRedirects: false,
        ),
      );

      final response = await dio.get('/auth/check');
      if (response.statusCode != 204) {
        return {
          'success': false,
          'error': '后端响应错误: ${response.statusCode}',
        };
      }

      return {
        'success': true,
        'auth_ok': true,
      };
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return {'success': true, 'auth_ok': false};
      }
      String msg = '连接失败: ';
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        msg += '连接超时';
      } else if (e.type == DioExceptionType.badResponse) {
        msg += '状态码 ${e.response?.statusCode}';
      } else {
        msg += '无法连接服务器，请检查地址与网络';
      }
      return {'success': false, 'error': msg};
    } catch (_) {
      return {'success': false, 'error': '连接测试失败，请重试'};
    }
  }
}
