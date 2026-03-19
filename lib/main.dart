import 'package:flutter/material.dart';

import 'src/config/app_config.dart';
import 'src/pages/otp_reader_page.dart';
import 'src/services/otp_api_service.dart';
import 'src/services/otp_message_filter.dart';
import 'src/services/sms_reader_service.dart';
import 'src/theme/app_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    this.smsReaderService = const SmsReaderService(),
    this.otpApiService = const OtpApiService(),
    this.otpMessageFilter = const OtpMessageFilter(),
    this.appConfig,
  });

  final SmsReaderService smsReaderService;
  final OtpApiService otpApiService;
  final OtpMessageFilter otpMessageFilter;
  final AppConfig? appConfig;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OTP Message Reader',
      theme: buildAppTheme(),
      debugShowCheckedModeBanner: false,
      home: OtpReaderPage(
        smsReaderService: smsReaderService,
        otpApiService: otpApiService,
        otpMessageFilter: otpMessageFilter,
        appConfig: appConfig ?? defaultAppConfig,
      ),
    );
  }
}