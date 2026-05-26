class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8010/api',
  );

  static String get baseUrl => apiBaseUrl;
}
