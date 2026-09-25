import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

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
      final detail = data['error_message'] ?? data['detail'];
      if (detail is String) message = detail;
      hint = data['error_hint']?.toString();
      requestId = data['request_id']?.toString();
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
  bool includeRequestId = false,
}) {
  final info = parseApiErrorInfo(error, fallbackMessage: fallbackMessage);
  // Only translate documented application codes; exception prose is diagnostic.
  final message = switch (info.code) {
    'invalid_api_token' => '访问密钥无效，请重新连接',
    'parse_queue_unavailable' => '内容已保存，暂时无法开始解析',
    'capture_file_too_large' => '文件超过上传大小限制',
    'capture_file_empty' => '不能上传空文件',
    'capture_too_many_files' => '上传文件数量超过限制',
    'media_bookmark_exists' => '这个时间点已有书签',
    'discovery_source_disabled' => '请先启用这个订阅源',
    'favorites_platform_disabled' => '请先启用该平台的收藏同步',
    'source_kind_not_supported' || 'unsupported_platform' => '暂不支持这个来源',
    _ => fallbackMessage,
  };
  final parts = <String>[message];

  if (includeRequestId &&
      info.requestId != null &&
      info.requestId!.isNotEmpty) {
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
      onError: (DioException e, handler) async {
        final info = parseApiErrorInfo(e);
        if (e.response?.statusCode == 401 &&
            info.code == 'invalid_api_token' &&
            ref.mounted &&
            settings.apiToken.isNotEmpty &&
            ref.read(localSettingsProvider).apiToken == settings.apiToken) {
          await ref.read(localSettingsProvider.notifier).clearAuth();
        }
        return handler.next(e);
      },
    ),
  );

  return dio;
}
