import 'package:http/http.dart' as http;

import '../app_logger.dart';
import '../config/app_config.dart';

class OtpApiService {
  const OtpApiService({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<OtpApiResponse> sendLatestOtp(
    String otp, {
    required AppConfig appConfig,
  }) async {
    final client = _client ?? http.Client();
    final shouldCloseClient = _client == null;
    final requestUri = _buildLatestOtpUri(otp, appConfig);
    final headers = <String, String>{
      'origin': appConfig.apiOrigin,
      'referer': appConfig.apiReferer,
      'visa-client': appConfig.visaClientHeaderValue,
    };

    AppLogger.info(
      'OtpApiService',
      'Sending OTP to API.',
      data: <String, Object?>{
        'otpCode': otp,
        'uri': requestUri.toString(),
        'headers': headers,
      },
    );

    try {
      final response = await client.get(requestUri, headers: headers);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        AppLogger.warn(
          'OtpApiService',
          'OTP API returned a non-success status.',
          data: <String, Object?>{
            'otpCode': otp,
            'statusCode': response.statusCode,
            'bodyLength': response.body.length,
          },
        );
        throw OtpApiException('API request failed (${response.statusCode}).');
      }

      AppLogger.info(
        'OtpApiService',
        'OTP API request succeeded.',
        data: <String, Object?>{
          'otpCode': otp,
          'statusCode': response.statusCode,
          'bodyLength': response.body.length,
        },
      );

      return OtpApiResponse(
        statusCode: response.statusCode,
        body: response.body,
      );
    } on OtpApiException {
      rethrow;
    } catch (error, stackTrace) {
      AppLogger.error(
        'OtpApiService',
        'Failed to reach OTP API.',
        error: error,
        stackTrace: stackTrace,
        data: <String, Object?>{
          'otpCode': otp,
          'uri': requestUri.toString(),
        },
      );
      throw OtpApiException('Could not reach OTP API: $error');
    } finally {
      if (shouldCloseClient) {
        client.close();
      }
    }
  }

  Uri _buildLatestOtpUri(String otp, AppConfig appConfig) {
    final baseUri = Uri.parse(appConfig.apiBaseUrl);
    return baseUri.replace(
      pathSegments: <String>[
        ...baseUri.pathSegments.where((segment) => segment.isNotEmpty),
        'fetch',
        'latest',
        'otp',
      ],
      queryParameters: <String, String>{'otp': otp},
    );
  }
}

class OtpApiResponse {
  const OtpApiResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

class OtpApiException implements Exception {
  const OtpApiException(this.message);

  final String message;

  @override
  String toString() => message;
}