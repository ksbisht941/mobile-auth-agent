import '../models/otp_match.dart';
import '../models/sms_message.dart';

class OtpMessageFilter {
  const OtpMessageFilter();

  static const List<String> _keywords = <String>[
    'otp',
    'code',
    'verification',
    'verify',
    'passcode',
    'authentication',
    'auth code',
    'security code',
    'login code',
    'one-time password',
  ];

  static final RegExp _candidateCodePattern = RegExp(r'[0-9][0-9\-\s]{2,10}[0-9]');
  static final RegExp _nonDigitPattern = RegExp(r'[^0-9]');

  List<OtpMatch> filterMessages(
    Iterable<SmsMessage> messages, {
    Iterable<String> senderFilters = const <String>[],
  }) {
    final normalizedSenderFilters = _normalizeSenderFilters(senderFilters);

    return messages
        .map((message) => _matchMessage(message, normalizedSenderFilters))
        .whereType<OtpMatch>()
        .toList(growable: false);
  }

  OtpMatch? matchMessage(
    SmsMessage message, {
    Iterable<String> senderFilters = const <String>[],
  }) {
    return _matchMessage(message, _normalizeSenderFilters(senderFilters));
  }

  OtpMatch? _matchMessage(SmsMessage message, List<String> senderFilters) {
    final normalizedBody = message.body.toLowerCase();
    final matchedKeywords = _keywords
        .where(normalizedBody.contains)
        .toList(growable: false);

    if (matchedKeywords.isEmpty) {
      return null;
    }

    if (senderFilters.isNotEmpty && !_matchesSender(message.sender, senderFilters)) {
      return null;
    }

    final otpCode = _extractOtpCode(message.body);
    if (otpCode == null) {
      return null;
    }

    return OtpMatch(
      message: message,
      otpCode: otpCode,
      matchedKeywords: matchedKeywords,
    );
  }

  String? _extractOtpCode(String body) {
    for (final match in _candidateCodePattern.allMatches(body)) {
      final candidate = match.group(0);
      if (candidate == null) {
        continue;
      }

      final digitsOnly = candidate.replaceAll(_nonDigitPattern, '');
      if (digitsOnly.length >= 4 && digitsOnly.length <= 8) {
        return digitsOnly;
      }
    }

    return null;
  }

  List<String> _normalizeSenderFilters(Iterable<String> senderFilters) {
    return senderFilters
        .map((filter) => filter.trim().toLowerCase())
        .where((filter) => filter.isNotEmpty)
        .toList(growable: false);
  }

  bool _matchesSender(String sender, List<String> senderFilters) {
    final normalizedSender = sender.toLowerCase();
    return senderFilters.any(normalizedSender.contains);
  }
}