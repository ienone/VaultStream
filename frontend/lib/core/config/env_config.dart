import 'package:flutter/foundation.dart';

class EnvConfig {
  static String get baseUrl {
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.isNotEmpty) return configured;
    return kIsWeb
        ? '${Uri.base.origin}/api/v1'
        : 'http://localhost:8000/api/v1';
  }

  static const String apiToken = String.fromEnvironment(
    'API_TOKEN',
    defaultValue: '', // 不再提供硬编码默认值，强制走 ConnectPage
  );

  static const bool debugLog = bool.fromEnvironment(
    'DEBUG_LOG',
    defaultValue: false,
  );
}
