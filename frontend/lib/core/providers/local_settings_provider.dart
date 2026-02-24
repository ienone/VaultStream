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
        ),
      );

      // 1. 先尝试免鉴权探测后端
      final initResponse = await dio.get('/init-status');
      if (initResponse.statusCode != 200) {
        return {
          'success': false,
          'error': '后端响应错误: ${initResponse.statusCode}',
        };
      }

      final initData = initResponse.data;

      // 2. 尝试带 Token 鉴权 (如果有 Token)
      bool authOk = false;
      if (apiToken.isNotEmpty) {
        try {
          final authResponse = await dio.get(
            '/dashboard/stats',
            options: Options(headers: {'X-API-Token': apiToken}),
          );
          authOk = authResponse.statusCode == 200;
        } catch (_) {
          authOk = false;
        }
      }

      return {
        'success': true,
        'auth_ok': authOk,
        'needs_setup': initData['needs_setup'] ?? false,
        'version': initData['version'],
      };
    } on DioException catch (e) {
      String msg = '连接失败: ';
      if (e.type == DioExceptionType.connectionTimeout) {
        msg += '连接超时';
      } else if (e.type == DioExceptionType.badResponse) {
        msg += '状态码 ${e.response?.statusCode}';
      } else {
        msg += e.message ?? '未知错误';
      }
      return {'success': false, 'error': msg};
    } catch (e) {
      return {'success': false, 'error': '未知错误: $e'};
    }
  }
}
