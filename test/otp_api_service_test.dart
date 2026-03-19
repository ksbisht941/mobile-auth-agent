import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:otp_message_reader/src/config/app_config.dart';
import 'package:otp_message_reader/src/services/otp_api_service.dart';

class RecordingClient extends http.BaseClient {
  RecordingClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _handler(request);
}

void main() {
  const appConfig = AppConfig(apiBaseUrl: 'https://api.example.com/api');

  test('builds the latest OTP GET request with required headers', () async {
    late http.BaseRequest capturedRequest;
    final service = OtpApiService(
      client: RecordingClient((request) async {
        capturedRequest = request;
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable(const <List<int>>[]),
          200,
        );
      }),
    );

    final response = await service.sendLatestOtp('123456', appConfig: appConfig);

    expect(capturedRequest.method, 'GET');
    expect(
      capturedRequest.url.toString(),
      'https://api.example.com/api/fetch/latest/otp?otp=123456',
    );
    expect(capturedRequest.headers['origin'], 'https://visa2fly.com');
    expect(capturedRequest.headers['referer'], 'https://visa2fly.com/');
    expect(capturedRequest.headers['visa-client'], '1');
    expect(response.isSuccess, isTrue);
  });

  test('throws a readable exception when the API returns a non-success status', () async {
    final service = OtpApiService(
      client: RecordingClient((request) async {
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable(const <List<int>>[]),
          500,
        );
      }),
    );

    await expectLater(
      () => service.sendLatestOtp('123456', appConfig: appConfig),
      throwsA(
        isA<OtpApiException>().having(
          (error) => error.message,
          'message',
          'API request failed (500).',
        ),
      ),
    );
  });
}