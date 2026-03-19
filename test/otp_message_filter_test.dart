import 'package:flutter_test/flutter_test.dart';
import 'package:otp_message_reader/src/models/sms_message.dart';
import 'package:otp_message_reader/src/services/otp_message_filter.dart';

void main() {
  const filter = OtpMessageFilter();

  SmsMessage message(String body, {String sender = 'Sender'}) {
    return SmsMessage(
      id: '1',
      sender: sender,
      body: body,
      receivedAt: DateTime(2026, 1, 1),
      type: 1,
    );
  }

  test('matches messages containing OTP keywords and digits', () {
    final match = filter.matchMessage(
      message('Your verification code is 123456.'),
    );

    expect(match, isNotNull);
    expect(match?.otpCode, '123456');
  });

  test('normalizes hyphenated codes', () {
    final match = filter.matchMessage(
      message('Use security code 123-456 to continue.'),
    );

    expect(match, isNotNull);
    expect(match?.otpCode, '123456');
  });

  test('rejects numeric messages without OTP keywords', () {
    final match = filter.matchMessage(
      message('Meet me at 123456 Main Street.'),
    );

    expect(match, isNull);
  });

  test('rejects keyword-only messages without numeric code', () {
    final match = filter.matchMessage(
      message('Your verification code will arrive soon.'),
    );

    expect(match, isNull);
  });

  test('applies sender name filters to OTP matches', () {
    final matches = filter.filterMessages(
      <SmsMessage>[
        message('Your verification code is 123456.', sender: 'Bank'),
        message('Your verification code is 654321.', sender: 'Shop'),
      ],
      senderFilters: const <String>['bank'],
    );

    expect(matches, hasLength(1));
    expect(matches.single.message.sender, 'Bank');
    expect(matches.single.otpCode, '123456');
  });

  test('matches sender phone number fragments', () {
    final match = filter.matchMessage(
      message(
        'Your verification code is 123456.',
        sender: '+66 8123 4567',
      ),
      senderFilters: const <String>['8123'],
    );

    expect(match, isNotNull);
    expect(match?.otpCode, '123456');
  });
}