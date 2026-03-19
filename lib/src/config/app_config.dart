class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    this.apiOrigin = 'https://visa2fly.com',
    this.apiReferer = 'https://visa2fly.com/',
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
  // apiBaseUrl: 'http://172.16.16.120:3000/api',
  apiBaseUrl: 'https://devapi.visa2fly.com/api',
  apiOrigin: 'https://visa2fly.com',
  apiReferer: 'https://visa2fly.com/',
  visaClientHeaderValue: '1',
  senderFilters: <String>[],
);