class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    this.apiOrigin = 'https://example.com',
    this.apiReferer = 'https://example.com/',
    this.visaClientHeaderValue = '1',
    this.senderFilters = const <String>[],
  });

  final String apiBaseUrl;
  final String apiOrigin;
  final String apiReferer;
  final String visaClientHeaderValue;
  final List<String> senderFilters;
}

const defaultAppConfig = AppConfig(
  apiBaseUrl: 'https://example.com/api',
  apiOrigin: 'https://example.com',
  apiReferer: 'https://example.com/',
  visaClientHeaderValue: '1',
  senderFilters: <String>[],
);