import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/api_client.dart';
import 'platform_health_provider.dart';

part 'platform_auth_controller.g.dart';

class PlatformAuthSession {
  const PlatformAuthSession({
    required this.sessionId,
    required this.platform,
    required this.status,
    this.message,
    this.qrcodeB64,
    this.captchaUrl,
  });

  final String sessionId;
  final String platform;
  final String status;
  final String? message;
  final String? qrcodeB64;
  final String? captchaUrl;

  bool get isTerminal =>
      const {'success', 'timeout', 'failed'}.contains(status);

  bool get succeeded => status == 'success';

  factory PlatformAuthSession.fromJson(Map<String, dynamic> json) {
    return PlatformAuthSession(
      sessionId: (json['session_id'] ?? '').toString(),
      platform: (json['platform'] ?? '').toString(),
      status: (json['status'] ?? 'failed').toString(),
      message: json['message']?.toString(),
      qrcodeB64: json['qrcode_b64']?.toString(),
      captchaUrl: json['captcha_url']?.toString(),
    );
  }
}

class PlatformAuthResult {
  const PlatformAuthResult({
    required this.ok,
    required this.message,
    this.isValid,
  });

  final bool ok;
  final String message;
  final bool? isValid;
}

class PlatformAuthException implements Exception {
  const PlatformAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _pendingKey(String platform, String action) => '$platform:$action';

@Riverpod(keepAlive: true)
class PlatformAuthActions extends _$PlatformAuthActions {
  @override
  Set<String> build() => const <String>{};

  bool isPending(String platform, String action) =>
      state.contains(_pendingKey(platform, action));

  Future<T> _run<T>(
    String platform,
    String action,
    Future<T> Function() body,
  ) async {
    final key = _pendingKey(platform, action);
    if (state.contains(key)) {
      throw const PlatformAuthException('该操作正在执行中');
    }
    state = {...state, key};
    try {
      return await body();
    } on PlatformAuthException {
      rethrow;
    } catch (error) {
      throw PlatformAuthException(
        formatApiErrorMessage(error, fallbackMessage: '平台认证操作失败'),
      );
    } finally {
      state = {...state}..remove(key);
    }
  }

  Future<PlatformAuthSession> startSession(String platform) {
    return _run(platform, 'login', () async {
      final response = await ref
          .read(apiClientProvider)
          .post('/browser-auth/session/$platform');
      return PlatformAuthSession.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    });
  }

  Future<PlatformAuthSession> readSession(String sessionId) async {
    try {
      final response = await ref
          .read(apiClientProvider)
          .get('/browser-auth/session/$sessionId/status');
      return PlatformAuthSession.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } catch (error) {
      throw PlatformAuthException(
        formatApiErrorMessage(error, fallbackMessage: '无法读取登录状态'),
      );
    }
  }

  Future<void> cancelSession(String sessionId) async {
    try {
      await ref
          .read(apiClientProvider)
          .delete('/browser-auth/session/$sessionId');
    } catch (error) {
      throw PlatformAuthException(
        formatApiErrorMessage(error, fallbackMessage: '无法取消登录会话'),
      );
    }
  }

  Future<PlatformAuthResult> check(String platform) {
    return _run(platform, 'check', () async {
      final response = await ref
          .read(apiClientProvider)
          .post('/browser-auth/$platform/check');
      final data = Map<String, dynamic>.from(response.data as Map);
      final valid = data['is_valid'] == true;
      ref.invalidate(platformHealthProvider);
      return PlatformAuthResult(
        ok: true,
        isValid: valid,
        message: valid ? '登录状态有效' : '登录已失效，请重新登录',
      );
    });
  }

  Future<PlatformAuthResult> logout(String platform) {
    return _run(platform, 'logout', () async {
      await ref.read(apiClientProvider).delete('/browser-auth/$platform');
      ref.invalidate(platformHealthProvider);
      return const PlatformAuthResult(ok: true, message: '已清除平台登录');
    });
  }

  void refreshHealth() => ref.invalidate(platformHealthProvider);
}
