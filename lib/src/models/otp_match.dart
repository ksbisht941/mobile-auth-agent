import 'sms_message.dart';

class OtpMatch {
  const OtpMatch({
    required this.message,
    required this.otpCode,
    required this.matchedKeywords,
  });

  final SmsMessage message;
  final String otpCode;
  final List<String> matchedKeywords;
}