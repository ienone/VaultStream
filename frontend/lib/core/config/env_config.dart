class EnvConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://localhost:8000/api/v1',
  );

  static const String apiToken = String.fromEnvironment(
    'API_TOKEN',
    defaultValue: '', // 不再提供硬编码默认值，强制走 ConnectPage
  );

  static const bool debugLog = bool.fromEnvironment(
    'DEBUG_LOG',
    defaultValue: true,
  );
}
