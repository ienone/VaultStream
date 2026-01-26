import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../config/env_config.dart';
import '../providers/local_settings_provider.dart';

part 'api_client.g.dart';

@riverpod
Dio apiClient(Ref ref) {
  final settings = ref.watch(localSettingsProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: settings.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'X-API-Token': settings.apiToken},
    ),
  );

  // 基础拦截器逻辑
  dio.interceptors.add(
    InterceptorsWrapper(
      onError: (DioException e, handler) {
        // 在这里可以处理全局错误，如 401 跳转
        if (e.response?.statusCode == 401) {
          // Log or trigger auth flow
        }
        return handler.next(e);
      },
    ),
  );

  if (EnvConfig.debugLog) {
    dio.interceptors.add(
      LogInterceptor(
        responseBody: true,
        requestHeader: true,
        requestBody: true,
      ),
    );
  }

  return dio;
}
