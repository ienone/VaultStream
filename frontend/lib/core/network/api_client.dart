import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../config/env_config.dart';
import '../providers/local_settings_provider.dart';

part 'api_client.g.dart';

class ApiErrorInfo {
  const ApiErrorInfo({
    required this.message,
    this.code,
    this.hint,
    this.requestId,
  });

  final String message;
  final String? code;
  final String? hint;
  final String? requestId;
}

ApiErrorInfo parseApiErrorInfo(
  Object error, {
  String fallbackMessage = '请求失败，请稍后重试',
}) {
  if (error is DioException) {
    final response = error.response;
    final data = response?.data;
    String? code;
    String? message;
    String? hint;
    String? requestId;

    if (data is Map) {
      code = data['error_code']?.toString();
      message = data['error_message']?.toString() ?? data['detail']?.toString();
      hint = data['error_hint']?.toString();
      requestId = data['request_id']?.toString();
    } else if (data is String && data.trim().isNotEmpty) {
      message = data.trim();
    }

    requestId ??= response?.headers.value('x-request-id');
    final resolvedMessage = (message == null || message.trim().isEmpty)
        ? fallbackMessage
        : message.trim();
    return ApiErrorInfo(
      message: resolvedMessage,
      code: code,
      hint: hint,
      requestId: requestId,
    );
  }

  return ApiErrorInfo(message: fallbackMessage);
}

String formatApiErrorMessage(
  Object error, {
  String fallbackMessage = '请求失败，请稍后重试',
  bool includeRequestId = true,
}) {
  final info = parseApiErrorInfo(error, fallbackMessage: fallbackMessage);
  final parts = <String>[];
  if (info.hint != null && info.hint!.trim().isNotEmpty) {
    parts.add(info.hint!.trim());
  } else {
    parts.add(info.message);
  }

  if (includeRequestId && info.requestId != null && info.requestId!.isNotEmpty) {
    final rid = info.requestId!;
    final shortId = rid.length > 8 ? rid.substring(0, 8) : rid;
    parts.add('RID:$shortId');
  }
  return parts.join(' | ');
}

@riverpod
Dio apiClient(Ref ref) {
  final settings = ref.watch(localSettingsProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: settings.baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'X-API-Token': settings.apiToken},
      followRedirects: false,
      validateStatus: (status) => status != null && status < 400,
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onError: (DioException e, handler) {
        final info = parseApiErrorInfo(e);
        if (EnvConfig.debugLog) {
          // ignore: avoid_print
          print('API error: code=${info.code} message=${info.message} rid=${info.requestId}');
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

