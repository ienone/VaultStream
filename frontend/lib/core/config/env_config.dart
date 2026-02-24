class EnvConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api/v1',
  );

  static const String apiToken = String.fromEnvironment(
    'API_TOKEN',
    defaultValue: '114514', // 建议通过 --dart-define 传入
  );

  static const bool debugLog = bool.fromEnvironment(
    'DEBUG_LOG',
    defaultValue: true,
  );
}
