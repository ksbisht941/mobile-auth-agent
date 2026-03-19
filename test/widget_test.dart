import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otp_message_reader/main.dart';
import 'package:otp_message_reader/src/config/app_config.dart';
import 'package:otp_message_reader/src/models/api_call_history_entry.dart';
import 'package:otp_message_reader/src/models/sms_message.dart';
import 'package:otp_message_reader/src/services/otp_api_service.dart';
import 'package:otp_message_reader/src/services/sms_reader_service.dart';
import 'package:otp_message_reader/src/theme/app_theme.dart';

const _testAppConfig = AppConfig(apiBaseUrl: 'https://example.com/api');

const _testAutoHandleAppConfig = AppConfig(
  apiBaseUrl: 'https://example.com/api',
  autoHandleEnabled: true,
);

class FakeSmsReaderService extends SmsReaderService {
  FakeSmsReaderService({
    bool initialPermission = true,
    this.permissionRequestResult = true,
    this.messages,
    int initialPendingBackgroundMessages = 0,
    bool initialDefaultDialer = false,
    this.defaultDialerRequestResult = false,
  }) : _hasPermission = initialPermission,
       _pendingBackgroundMessages = initialPendingBackgroundMessages,
       _isDefaultDialer = initialDefaultDialer;

  bool _hasPermission;
  int _pendingBackgroundMessages;
  bool _isDefaultDialer;
  final bool permissionRequestResult;
  final bool defaultDialerRequestResult;
  final StreamController<List<SmsMessage>> _incomingMessagesController =
      StreamController<List<SmsMessage>>.broadcast();
  Future<List<SmsMessage>> Function()? readAllMessagesHandler;
  List<SmsMessage>? messages;
  Object? showApiSuccessNotificationError;
  Object? saveApiCallHistoryError;
  AppConfig? syncedBackgroundApiConfig;
  AppConfig? loadedPersistedAppConfig;
  int isDefaultDialerChecks = 0;
  int defaultDialerRoleRequests = 0;
  final List<String> backgroundHandledOtpKeys = <String>[];
  final List<FakeApiSuccessNotification> apiSuccessNotifications =
      <FakeApiSuccessNotification>[];
  final List<FakeApiCallHistoryEntry> apiCallHistoryEntries =
      <FakeApiCallHistoryEntry>[];

  @override
  bool get supportsSmsReading => true;

  @override
  Future<bool> hasSmsPermission() async => _hasPermission;

  @override
  Future<bool> requestSmsPermission() async {
    _hasPermission = permissionRequestResult;
    return _hasPermission;
  }

  @override
  Future<void> ensureNotificationPermission() async {}

  @override
  Future<AppConfig> loadPersistedAppConfig(AppConfig baseConfig) async {
    return loadedPersistedAppConfig ?? baseConfig;
  }

  @override
  Future<void> syncBackgroundApiConfig(AppConfig appConfig) async {
    syncedBackgroundApiConfig = appConfig;
  }

  @override
  Future<bool> isDefaultDialer() async {
    isDefaultDialerChecks += 1;
    return _isDefaultDialer;
  }

  @override
  Future<bool> requestDefaultDialerRole() async {
    defaultDialerRoleRequests += 1;
    _isDefaultDialer = defaultDialerRequestResult;
    return _isDefaultDialer;
  }

  @override
  Future<void> showApiSuccessNotification({
    required String otpCode,
    required String sender,
    required String receivedAtLabel,
  }) async {
    if (showApiSuccessNotificationError case final Object error) {
      throw error;
    }

    apiSuccessNotifications.add(
      FakeApiSuccessNotification(
        otpCode: otpCode,
        sender: sender,
        receivedAtLabel: receivedAtLabel,
      ),
    );
  }

  @override
  Future<void> saveApiCallHistoryEntry({
    required String otpCode,
    required String sender,
    required DateTime smsReceivedAt,
    required DateTime apiCalledAt,
    required bool isSuccess,
    int? statusCode,
    String? errorMessage,
  }) async {
    if (saveApiCallHistoryError case final Object error) {
      throw error;
    }

    apiCallHistoryEntries.add(
      FakeApiCallHistoryEntry(
        otpCode: otpCode,
        sender: sender,
        smsReceivedAt: smsReceivedAt,
        apiCalledAt: apiCalledAt,
        isSuccess: isSuccess,
        statusCode: statusCode,
        errorMessage: errorMessage,
      ),
    );

    if (apiCallHistoryEntries.length > 5) {
      apiCallHistoryEntries.removeRange(0, apiCallHistoryEntries.length - 5);
    }
  }

  @override
  Future<List<ApiCallHistoryEntry>> getApiCallHistory() async {
    return apiCallHistoryEntries.reversed
        .map(
          (entry) => ApiCallHistoryEntry(
            otpCode: entry.otpCode,
            sender: entry.sender,
            smsReceivedAt: entry.smsReceivedAt,
            apiCalledAt: entry.apiCalledAt,
            isSuccess: entry.isSuccess,
            statusCode: entry.statusCode,
            errorMessage: entry.errorMessage,
          ),
        )
        .toList(growable: false);
  }

  @override
  Stream<List<SmsMessage>> watchIncomingMessages() =>
      _incomingMessagesController.stream;

  @override
  Future<int> consumePendingBackgroundMessages() async {
    final pendingMessages = _pendingBackgroundMessages;
    _pendingBackgroundMessages = 0;
    return pendingMessages;
  }

  @override
  Future<List<String>> consumeBackgroundHandledOtpKeys() async {
    final keys = List<String>.from(backgroundHandledOtpKeys);
    backgroundHandledOtpKeys.clear();
    return keys;
  }

  void emitIncomingMessage([
    List<SmsMessage> incomingMessages = const <SmsMessage>[],
  ]) {
    _incomingMessagesController.add(incomingMessages);
  }

  void queueBackgroundMessage() {
    _pendingBackgroundMessages += 1;
  }

  @override
  Future<List<SmsMessage>> readAllMessages() async {
    final handler = readAllMessagesHandler;
    if (handler != null) {
      return handler();
    }

    return messages ??
        <SmsMessage>[
          SmsMessage(
            id: '1',
            sender: 'Bank',
            body: 'Your verification code is 482913.',
            receivedAt: DateTime(2026, 1, 1),
            type: 1,
          ),
          SmsMessage(
            id: '2',
            sender: 'Friend',
            body: 'Dinner at 7?',
            receivedAt: DateTime(2026, 1, 1),
            type: 1,
          ),
        ];
  }
}

class FakeOtpApiService extends OtpApiService {
  FakeOtpApiService({
    this.failingOtp,
    this.errorMessage = 'API request failed (500).',
    this.sendLatestOtpCompleter,
  });

  final List<String> sentOtps = <String>[];
  final String? failingOtp;
  final String errorMessage;
  final Completer<void>? sendLatestOtpCompleter;

  @override
  Future<OtpApiResponse> sendLatestOtp(
    String otp, {
    required AppConfig appConfig,
  }) async {
    sentOtps.add(otp);

    final sendLatestOtpCompleter = this.sendLatestOtpCompleter;
    if (sendLatestOtpCompleter != null) {
      await sendLatestOtpCompleter.future;
    }

    if (otp == failingOtp) {
      throw OtpApiException(errorMessage);
    }

    return const OtpApiResponse(statusCode: 200, body: '{"success":true}');
  }
}

class FakeApiSuccessNotification {
  const FakeApiSuccessNotification({
    required this.otpCode,
    required this.sender,
    required this.receivedAtLabel,
  });

  final String otpCode;
  final String sender;
  final String receivedAtLabel;
}

class FakeApiCallHistoryEntry {
  const FakeApiCallHistoryEntry({
    required this.otpCode,
    required this.sender,
    required this.smsReceivedAt,
    required this.apiCalledAt,
    required this.isSuccess,
    this.statusCode,
    this.errorMessage,
  });

  final String otpCode;
  final String sender;
  final DateTime smsReceivedAt;
  final DateTime apiCalledAt;
  final bool isSuccess;
  final int? statusCode;
  final String? errorMessage;
}

void main() {
  testWidgets('falls back to default config when appConfig is null', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MyApp(
        appConfig: null,
        smsReaderService: FakeSmsReaderService(),
        otpApiService: FakeOtpApiService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mobile Auth Agent'), findsOneWidget);
  });

  testWidgets('syncs background API config on app startup', (
    WidgetTester tester,
  ) async {
    final smsReaderService = FakeSmsReaderService();
    const appConfig = AppConfig(
      apiBaseUrl: 'https://example.com/api',
      autoHandleEnabled: true,
      autoAnswerNumbers: <String>['+91 9999999999'],
      autoHangUpDelaySeconds: 35,
      postAnswerDtmfSteps: <PostAnswerDtmfStep>[
        PostAnswerDtmfStep(digit: '2', delaySeconds: 6),
        PostAnswerDtmfStep(digit: '8', delaySeconds: 12),
      ],
    );

    await tester.pumpWidget(
      MyApp(
        appConfig: appConfig,
        smsReaderService: smsReaderService,
        otpApiService: FakeOtpApiService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      smsReaderService.syncedBackgroundApiConfig?.apiBaseUrl,
      appConfig.apiBaseUrl,
    );
    expect(
      smsReaderService.syncedBackgroundApiConfig?.visaClientHeaderValue,
      appConfig.visaClientHeaderValue,
    );
    expect(
      smsReaderService.syncedBackgroundApiConfig?.autoAnswerNumbers,
      appConfig.autoAnswerNumbers,
    );
    expect(
      smsReaderService.syncedBackgroundApiConfig?.autoHangUpDelaySeconds,
      35,
    );
    expect(
      smsReaderService.syncedBackgroundApiConfig?.postAnswerDtmfSteps,
      const <PostAnswerDtmfStep>[
        PostAnswerDtmfStep(digit: '2', delaySeconds: 6),
        PostAnswerDtmfStep(digit: '8', delaySeconds: 12),
      ],
    );
  });

  testWidgets('shows auto-answer setup when a target number is configured', (
    WidgetTester tester,
  ) async {
    final smsReaderService = FakeSmsReaderService(initialDefaultDialer: false);

    await tester.pumpWidget(
      MyApp(
        appConfig: const AppConfig(
          apiBaseUrl: 'https://example.com/api',
          autoHandleEnabled: true,
          autoAnswerNumbers: <String>['+91 9999999999'],
        ),
        smsReaderService: smsReaderService,
        otpApiService: FakeOtpApiService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('auto-answer-card')), findsOneWidget);
    expect(find.text('Auto-answer configured calls'), findsOneWidget);
    expect(find.text('1 configured number'), findsOneWidget);
    expect(find.text('+91 9999999999'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('request-default-dialer-button')),
      findsOneWidget,
    );
    expect(find.text('Set as default phone app'), findsOneWidget);
    expect(smsReaderService.isDefaultDialerChecks, greaterThanOrEqualTo(1));
  });

  testWidgets('requests the default phone app role from the auto-answer card', (
    WidgetTester tester,
  ) async {
    final smsReaderService = FakeSmsReaderService(
      initialDefaultDialer: false,
      defaultDialerRequestResult: true,
    );

    await tester.pumpWidget(
      MyApp(
        appConfig: const AppConfig(
          apiBaseUrl: 'https://example.com/api',
          autoHandleEnabled: true,
          autoAnswerNumbers: <String>['+91 9999999999'],
        ),
        smsReaderService: smsReaderService,
        otpApiService: FakeOtpApiService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('request-default-dialer-button')),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(smsReaderService.defaultDialerRoleRequests, 1);
    expect(
      find.byKey(const ValueKey('request-default-dialer-button')),
      findsNothing,
    );
    expect(find.text('Set as default phone app'), findsNothing);
  });

  testWidgets('loads persisted runtime settings before syncing config', (
    WidgetTester tester,
  ) async {
    final smsReaderService = FakeSmsReaderService()
      ..loadedPersistedAppConfig = const AppConfig(
        apiBaseUrl: 'https://example.com/api',
        senderFilters: <String>['BANKOTP'],
        autoHandleEnabled: true,
        autoAnswerNumbers: <String>['+91 8888888888'],
        autoHangUpDelaySeconds: 45,
        postAnswerDtmfSteps: <PostAnswerDtmfStep>[
          PostAnswerDtmfStep(digit: '3', delaySeconds: 5),
          PostAnswerDtmfStep(digit: '7', delaySeconds: 11),
        ],
      );

    await tester.pumpWidget(
      MyApp(
        appConfig: const AppConfig(apiBaseUrl: 'https://example.com/api'),
        smsReaderService: smsReaderService,
        otpApiService: FakeOtpApiService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(smsReaderService.syncedBackgroundApiConfig?.senderFilters, <String>[
      'BANKOTP',
    ]);
    expect(
      smsReaderService.syncedBackgroundApiConfig?.autoHandleEnabled,
      isTrue,
    );
    expect(
      smsReaderService.syncedBackgroundApiConfig?.autoAnswerNumbers,
      <String>['+91 8888888888'],
    );
    expect(
      smsReaderService.syncedBackgroundApiConfig?.autoHangUpDelaySeconds,
      45,
    );
    expect(
      smsReaderService.syncedBackgroundApiConfig?.postAnswerDtmfSteps,
      const <PostAnswerDtmfStep>[
        PostAnswerDtmfStep(digit: '3', delaySeconds: 5),
        PostAnswerDtmfStep(digit: '7', delaySeconds: 11),
      ],
    );
    expect(find.text('1 configured number'), findsOneWidget);
    expect(find.text('+91 8888888888'), findsOneWidget);
  });

  testWidgets('saves updated runtime settings from the settings page', (
    WidgetTester tester,
  ) async {
    final smsReaderService = FakeSmsReaderService(initialDefaultDialer: false);

    await tester.pumpWidget(
      MyApp(
        appConfig: const AppConfig(apiBaseUrl: 'https://example.com/api'),
        smsReaderService: smsReaderService,
        otpApiService: FakeOtpApiService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-settings-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-auto-handle-switch')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('settings-sender-filters-field')),
      'BANKOTP\nVK-OTP',
    );
    await tester.ensureVisible(
      find.byKey(
        const ValueKey('settings-auto-answer-numbers-field'),
        skipOffstage: false,
      ),
    );
    await tester.pumpAndSettle();
    final autoAnswerNumbersField = tester.widget<TextField>(
      find.byKey(const ValueKey('settings-auto-answer-numbers-field')),
    );
    expect(autoAnswerNumbersField.keyboardType, TextInputType.multiline);
    expect(autoAnswerNumbersField.textInputAction, TextInputAction.newline);
    await tester.enterText(
      find.byKey(const ValueKey('settings-auto-answer-numbers-field')),
      '+91 7777777777\n+91 6666666666',
    );
    final autoHangUpDelayField = tester.widget<TextField>(
      find.byKey(const ValueKey('settings-auto-hangup-seconds-field')),
    );
    expect(autoHangUpDelayField.keyboardType, TextInputType.number);
    await tester.enterText(
      find.byKey(const ValueKey('settings-auto-hangup-seconds-field')),
      '45',
    );
    await tester.ensureVisible(
      find.byKey(
        const ValueKey('settings-post-answer-dtmf-add-step-button'),
        skipOffstage: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('settings-post-answer-dtmf-add-step-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('settings-post-answer-dtmf-add-step-button')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(
        const ValueKey('settings-post-answer-dtmf-digit-field-0'),
        skipOffstage: false,
      ),
    );
    await tester.pumpAndSettle();
    final firstDtmfDigitField = tester.widget<TextField>(
      find.byKey(const ValueKey('settings-post-answer-dtmf-digit-field-0')),
    );
    expect(
      firstDtmfDigitField.textCapitalization,
      TextCapitalization.characters,
    );
    await tester.enterText(
      find.byKey(const ValueKey('settings-post-answer-dtmf-digit-field-0')),
      '2',
    );
    final firstDtmfDelayField = tester.widget<TextField>(
      find.byKey(
        const ValueKey('settings-post-answer-dtmf-delay-seconds-field-0'),
      ),
    );
    expect(firstDtmfDelayField.keyboardType, TextInputType.number);
    await tester.enterText(
      find.byKey(
        const ValueKey('settings-post-answer-dtmf-delay-seconds-field-0'),
      ),
      '6',
    );
    await tester.enterText(
      find.byKey(const ValueKey('settings-post-answer-dtmf-digit-field-1')),
      '5',
    );
    await tester.enterText(
      find.byKey(
        const ValueKey('settings-post-answer-dtmf-delay-seconds-field-1'),
      ),
      '9',
    );
    await tester.tap(
      find.byKey(const ValueKey('settings-post-answer-dtmf-add-step-button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('settings-post-answer-dtmf-digit-field-2')),
      '8',
    );
    await tester.enterText(
      find.byKey(
        const ValueKey('settings-post-answer-dtmf-delay-seconds-field-2'),
      ),
      '12',
    );
    await tester.ensureVisible(
      find.byKey(
        const ValueKey('settings-post-answer-dtmf-remove-step-button-1'),
        skipOffstage: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('settings-post-answer-dtmf-remove-step-button-1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-settings-button')));
    await tester.pumpAndSettle();

    expect(
      smsReaderService.syncedBackgroundApiConfig?.autoHandleEnabled,
      isTrue,
    );
    expect(smsReaderService.syncedBackgroundApiConfig?.senderFilters, <String>[
      'BANKOTP',
      'VK-OTP',
    ]);
    expect(
      smsReaderService.syncedBackgroundApiConfig?.autoAnswerNumbers,
      <String>['+91 7777777777', '+91 6666666666'],
    );
    expect(
      smsReaderService.syncedBackgroundApiConfig?.autoHangUpDelaySeconds,
      45,
    );
    expect(
      smsReaderService.syncedBackgroundApiConfig?.postAnswerDtmfSteps,
      const <PostAnswerDtmfStep>[
        PostAnswerDtmfStep(digit: '2', delaySeconds: 6),
        PostAnswerDtmfStep(digit: '8', delaySeconds: 12),
      ],
    );
    expect(find.byKey(const ValueKey('auto-answer-card')), findsOneWidget);
    expect(find.text('2 configured numbers'), findsOneWidget);
    expect(find.text('+91 7777777777'), findsOneWidget);
    expect(find.text('+91 6666666666'), findsOneWidget);
  });

  testWidgets(
    'automatically loads OTP matches when SMS permission is already granted',
    (WidgetTester tester) async {
      final otpApiService = FakeOtpApiService();

      await tester.pumpWidget(
        MyApp(
          appConfig: _testAppConfig,
          smsReaderService: FakeSmsReaderService(),
          otpApiService: otpApiService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mobile Auth Agent'), findsOneWidget);
      expect(find.text('Messages scanned: 2'), findsOneWidget);
      expect(find.text('OTP matches found: 1'), findsOneWidget);
      expect(find.text('482913'), findsOneWidget);
      expect(otpApiService.sentOtps, isEmpty);
    },
  );

  testWidgets('uses settings-aligned typography on the home status card', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MyApp(
        appConfig: _testAppConfig,
        smsReaderService: FakeSmsReaderService(),
        otpApiService: FakeOtpApiService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OTP inbox'), findsOneWidget);

    final scannedFinder = find.text('Messages scanned: 2');
    final matchesFinder = find.text('OTP matches found: 1');
    final theme = Theme.of(tester.element(scannedFinder));
    final scannedText = tester.widget<Text>(scannedFinder);
    final matchesText = tester.widget<Text>(matchesFinder);

    expect(scannedText.style?.fontSize, theme.textTheme.titleMedium?.fontSize);
    expect(scannedText.style?.fontWeight, FontWeight.w700);
    expect(matchesText.style?.fontSize, theme.textTheme.bodyMedium?.fontSize);
    expect(matchesText.style?.color, AppColors.mutedText);
  });

  testWidgets(
    'does not resend the same OTP on manual refresh after the initial load',
    (WidgetTester tester) async {
      final otpApiService = FakeOtpApiService();

      await tester.pumpWidget(
        MyApp(
          appConfig: _testAppConfig,
          smsReaderService: FakeSmsReaderService(),
          otpApiService: otpApiService,
        ),
      );
      await tester.pumpAndSettle();

      expect(otpApiService.sentOtps, isEmpty);

      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(otpApiService.sentOtps, isEmpty);
    },
  );

  testWidgets(
    'manually resends an OTP when swiping right on the message tile',
    (WidgetTester tester) async {
      final smsReaderService = FakeSmsReaderService();
      final otpApiService = FakeOtpApiService();

      await tester.pumpWidget(
        MyApp(
          appConfig: _testAppConfig,
          smsReaderService: smsReaderService,
          otpApiService: otpApiService,
        ),
      );
      await tester.pumpAndSettle();

      expect(otpApiService.sentOtps, isEmpty);
      expect(smsReaderService.apiCallHistoryEntries, isEmpty);
      expect(smsReaderService.apiSuccessNotifications, isEmpty);

      final tileFinder = find.byKey(const ValueKey('otp-message-tile-1'));
      final tileWidth = tester.getSize(tileFinder).width;

      await tester.drag(tileFinder, Offset(tileWidth * 0.35, 0));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(otpApiService.sentOtps, <String>['482913']);
      expect(smsReaderService.apiCallHistoryEntries.length, 1);
      expect(smsReaderService.apiSuccessNotifications.length, 1);
      expect(find.text('482913'), findsOneWidget);
    },
  );

  testWidgets(
    'does not manually resend an OTP before the 30 percent swipe threshold',
    (WidgetTester tester) async {
      final otpApiService = FakeOtpApiService();

      await tester.pumpWidget(
        MyApp(
          appConfig: _testAppConfig,
          smsReaderService: FakeSmsReaderService(),
          otpApiService: otpApiService,
        ),
      );
      await tester.pumpAndSettle();

      final tileFinder = find.byKey(const ValueKey('otp-message-tile-1'));
      final tileWidth = tester.getSize(tileFinder).width;

      await tester.drag(tileFinder, Offset(tileWidth * 0.25, 0));
      await tester.pumpAndSettle();

      expect(otpApiService.sentOtps, isEmpty);
    },
  );

  testWidgets('caps the manual swipe reveal at 40 percent before sending', (
    WidgetTester tester,
  ) async {
    final otpApiService = FakeOtpApiService();

    await tester.pumpWidget(
      MyApp(
        appConfig: _testAppConfig,
        smsReaderService: FakeSmsReaderService(),
        otpApiService: otpApiService,
      ),
    );
    await tester.pumpAndSettle();

    final tileFinder = find.byKey(const ValueKey('otp-message-tile-1'));
    final swipeChildFinder = find.byKey(
      const ValueKey('otp-message-swipe-child-1'),
    );
    final tileWidth = tester.getSize(tileFinder).width;
    final gesture = await tester.startGesture(tester.getCenter(tileFinder));

    for (var step = 0; step < 8; step++) {
      await gesture.moveBy(Offset(tileWidth * 0.1, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      tester.widget<AnimatedContainer>(swipeChildFinder).transform?.storage[12],
      moreOrLessEquals(tileWidth * 0.4, epsilon: 1),
    );
    expect(otpApiService.sentOtps, isEmpty);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(otpApiService.sentOtps, <String>['482913']);
    expect(
      tester.widget<AnimatedContainer>(swipeChildFinder).transform?.storage[12],
      moreOrLessEquals(0, epsilon: 1),
    );
  });

  testWidgets(
    'snaps the message tile back while a manual swipe send is still in flight',
    (WidgetTester tester) async {
      final sendLatestOtpCompleter = Completer<void>();
      final otpApiService = FakeOtpApiService(
        sendLatestOtpCompleter: sendLatestOtpCompleter,
      );

      await tester.pumpWidget(
        MyApp(
          appConfig: _testAppConfig,
          smsReaderService: FakeSmsReaderService(),
          otpApiService: otpApiService,
        ),
      );
      await tester.pumpAndSettle();

      final tileFinder = find.byKey(const ValueKey('otp-message-tile-1'));
      final swipeChildFinder = find.byKey(
        const ValueKey('otp-message-swipe-child-1'),
      );
      final tileWidth = tester.getSize(tileFinder).width;

      await tester.drag(tileFinder, Offset(tileWidth * 0.35, 0));
      await tester.pumpAndSettle();

      expect(otpApiService.sentOtps, <String>['482913']);

      expect(
        tester
            .widget<AnimatedContainer>(swipeChildFinder)
            .transform
            ?.storage[12],
        moreOrLessEquals(0, epsilon: 1),
      );
      expect(find.text('482913'), findsOneWidget);

      sendLatestOtpCompleter.complete();
      await tester.pumpAndSettle();

      expect(find.text('482913'), findsOneWidget);
    },
  );

  testWidgets('refreshes automatically when a new SMS arrives', (
    WidgetTester tester,
  ) async {
    final smsReaderService = FakeSmsReaderService(messages: <SmsMessage>[]);

    await tester.pumpWidget(
      MyApp(
        appConfig: _testAppConfig,
        smsReaderService: smsReaderService,
        otpApiService: FakeOtpApiService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Messages scanned: 0'), findsOneWidget);
    expect(find.text('OTP matches found: 0'), findsOneWidget);

    smsReaderService.messages = <SmsMessage>[
      SmsMessage(
        id: '3',
        sender: 'Bank',
        body: 'Your verification code is 991122.',
        receivedAt: DateTime(2026, 1, 1),
        type: 1,
      ),
    ];

    smsReaderService.emitIncomingMessage();

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Messages scanned: 1'), findsOneWidget);
    expect(find.text('OTP matches found: 1'), findsOneWidget);
    expect(find.text('991122'), findsOneWidget);
  });

  testWidgets(
    'sends only the latest newly detected OTP to the API when a new SMS arrives',
    (WidgetTester tester) async {
      final smsReaderService = FakeSmsReaderService(messages: <SmsMessage>[]);
      final otpApiService = FakeOtpApiService();

      await tester.pumpWidget(
        MyApp(
          appConfig: _testAutoHandleAppConfig,
          smsReaderService: smsReaderService,
          otpApiService: otpApiService,
        ),
      );
      await tester.pumpAndSettle();

      smsReaderService.messages = <SmsMessage>[
        SmsMessage(
          id: '3',
          sender: 'Bank',
          body: 'Your verification code is 991122.',
          receivedAt: DateTime(2026, 1, 1, 0, 1),
          type: 1,
        ),
        SmsMessage(
          id: '4',
          sender: 'Shop',
          body: 'Use OTP 778899 to complete your sign in.',
          receivedAt: DateTime(2026, 1, 1, 0, 2),
          type: 1,
        ),
      ];

      smsReaderService.emitIncomingMessage();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(otpApiService.sentOtps, <String>['778899']);
      expect(smsReaderService.apiSuccessNotifications.length, 1);
      expect(smsReaderService.apiSuccessNotifications[0].otpCode, '778899');
      expect(smsReaderService.apiSuccessNotifications[0].sender, 'Shop');
      expect(smsReaderService.apiCallHistoryEntries.length, 1);
      expect(smsReaderService.apiCallHistoryEntries[0].otpCode, '778899');
      expect(smsReaderService.apiCallHistoryEntries[0].isSuccess, isTrue);
      expect(smsReaderService.apiCallHistoryEntries[0].statusCode, 200);
    },
  );

  testWidgets(
    'allows auto-send retry when a new message has the same sender OTP and time',
    (WidgetTester tester) async {
      final receivedAt = DateTime(2026, 1, 1, 0, 1);
      final smsReaderService = FakeSmsReaderService(messages: <SmsMessage>[]);
      final otpApiService = FakeOtpApiService();

      await tester.pumpWidget(
        MyApp(
          appConfig: _testAutoHandleAppConfig,
          smsReaderService: smsReaderService,
          otpApiService: otpApiService,
        ),
      );
      await tester.pumpAndSettle();

      smsReaderService.messages = <SmsMessage>[
        SmsMessage(
          id: '51',
          sender: 'Bank',
          body: 'Your verification code is 974290.',
          receivedAt: receivedAt,
          type: 1,
        ),
      ];
      smsReaderService.emitIncomingMessage();
      await tester.pump();
      await tester.pumpAndSettle();

      smsReaderService.messages = <SmsMessage>[
        SmsMessage(
          id: '51',
          sender: 'Bank',
          body: 'Your verification code is 974290.',
          receivedAt: receivedAt,
          type: 1,
        ),
        SmsMessage(
          id: '52',
          sender: 'Bank',
          body: 'Your verification code is 974290.',
          receivedAt: receivedAt,
          type: 1,
        ),
      ];
      smsReaderService.emitIncomingMessage();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(otpApiService.sentOtps, <String>['974290', '974290']);
    },
  );

  testWidgets(
    'requests a system notification when sending a new OTP to the API succeeds',
    (WidgetTester tester) async {
      final smsReaderService = FakeSmsReaderService(messages: <SmsMessage>[]);
      final otpApiService = FakeOtpApiService();

      await tester.pumpWidget(
        MyApp(
          appConfig: _testAutoHandleAppConfig,
          smsReaderService: smsReaderService,
          otpApiService: otpApiService,
        ),
      );
      await tester.pumpAndSettle();

      smsReaderService.messages = <SmsMessage>[
        SmsMessage(
          id: '3',
          sender: 'Bank',
          body: 'Your verification code is 991122.',
          receivedAt: DateTime(2026, 1, 1),
          type: 1,
        ),
      ];

      smsReaderService.emitIncomingMessage();
      await tester.pump();
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(ListView));
      final localizations = MaterialLocalizations.of(context);
      final expectedReceivedAtLabel =
          '${localizations.formatMediumDate(DateTime(2026, 1, 1))}, '
          '${localizations.formatTimeOfDay(const TimeOfDay(hour: 0, minute: 0))}';

      expect(smsReaderService.apiSuccessNotifications.length, 1);
      expect(smsReaderService.apiSuccessNotifications.first.otpCode, '991122');
      expect(smsReaderService.apiSuccessNotifications.first.sender, 'Bank');
      expect(
        smsReaderService.apiSuccessNotifications.first.receivedAtLabel,
        expectedReceivedAtLabel,
      );
    },
  );

  testWidgets('does not treat API history save failures as API send failures', (
    WidgetTester tester,
  ) async {
    final smsReaderService = FakeSmsReaderService(messages: <SmsMessage>[])
      ..saveApiCallHistoryError = PlatformException(
        code: 'history_write_failed',
        message: 'Could not persist API history.',
      );
    final otpApiService = FakeOtpApiService();

    await tester.pumpWidget(
      MyApp(
        appConfig: _testAutoHandleAppConfig,
        smsReaderService: smsReaderService,
        otpApiService: otpApiService,
      ),
    );
    await tester.pumpAndSettle();

    smsReaderService.messages = <SmsMessage>[
      SmsMessage(
        id: 'history-failure-1',
        sender: 'Bank',
        body: 'Your verification code is 991122.',
        receivedAt: DateTime(2026, 1, 1),
        type: 1,
      ),
    ];

    smsReaderService.emitIncomingMessage();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(otpApiService.sentOtps, <String>['991122']);
    expect(
      find.textContaining('Could not send OTP 991122 to API'),
      findsNothing,
    );
    expect(smsReaderService.apiSuccessNotifications.length, 1);
    expect(smsReaderService.apiCallHistoryEntries, isEmpty);
  });

  testWidgets(
    'does not treat API success notification failures as API send failures',
    (WidgetTester tester) async {
      final smsReaderService = FakeSmsReaderService(messages: <SmsMessage>[])
        ..showApiSuccessNotificationError = PlatformException(
          code: 'notification_failed',
          message: 'Could not show API success notification.',
        );
      final otpApiService = FakeOtpApiService();

      await tester.pumpWidget(
        MyApp(
          appConfig: _testAutoHandleAppConfig,
          smsReaderService: smsReaderService,
          otpApiService: otpApiService,
        ),
      );
      await tester.pumpAndSettle();

      smsReaderService.messages = <SmsMessage>[
        SmsMessage(
          id: 'notification-failure-1',
          sender: 'Bank',
          body: 'Your verification code is 991122.',
          receivedAt: DateTime(2026, 1, 1),
          type: 1,
        ),
      ];

      smsReaderService.emitIncomingMessage();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(otpApiService.sentOtps, <String>['991122']);
      expect(
        find.textContaining('Could not send OTP 991122 to API'),
        findsNothing,
      );
      expect(smsReaderService.apiCallHistoryEntries.length, 1);
      expect(smsReaderService.apiSuccessNotifications, isEmpty);
    },
  );

  testWidgets('shows an error when sending a new OTP to the API fails', (
    WidgetTester tester,
  ) async {
    final smsReaderService = FakeSmsReaderService(messages: <SmsMessage>[]);
    final otpApiService = FakeOtpApiService(failingOtp: '991122');

    await tester.pumpWidget(
      MyApp(
        appConfig: _testAutoHandleAppConfig,
        smsReaderService: smsReaderService,
        otpApiService: otpApiService,
      ),
    );
    await tester.pumpAndSettle();

    smsReaderService.messages = <SmsMessage>[
      SmsMessage(
        id: '3',
        sender: 'Bank',
        body: 'Your verification code is 991122.',
        receivedAt: DateTime(2026, 1, 1),
        type: 1,
      ),
    ];

    smsReaderService.emitIncomingMessage();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('991122'), findsOneWidget);
    expect(
      find.text('Could not send OTP 991122 to API: API request failed (500).'),
      findsOneWidget,
    );
    expect(smsReaderService.apiCallHistoryEntries.length, 1);
    expect(smsReaderService.apiCallHistoryEntries.first.otpCode, '991122');
    expect(smsReaderService.apiCallHistoryEntries.first.isSuccess, isFalse);
    expect(
      smsReaderService.apiCallHistoryEntries.first.errorMessage,
      'API request failed (500).',
    );
  });

  testWidgets('keeps only the last 5 API call history entries', (
    WidgetTester tester,
  ) async {
    final smsReaderService = FakeSmsReaderService(messages: <SmsMessage>[]);

    for (var index = 0; index < 55; index += 1) {
      final otpCode = (100001 + index).toString();
      await smsReaderService.saveApiCallHistoryEntry(
        otpCode: otpCode,
        sender: 'Bank $index',
        smsReceivedAt: DateTime(2026, 1, 1).add(Duration(minutes: index)),
        apiCalledAt: DateTime(
          2026,
          1,
          1,
        ).add(Duration(minutes: index, seconds: 5)),
        isSuccess: true,
        statusCode: 200,
      );
    }

    expect(smsReaderService.apiCallHistoryEntries.length, 5);
    expect(smsReaderService.apiCallHistoryEntries.first.otpCode, '100051');
    expect(smsReaderService.apiCallHistoryEntries.last.otpCode, '100055');
  });

  testWidgets('shows API history inside the settings page', (
    WidgetTester tester,
  ) async {
    final smsReaderService = FakeSmsReaderService(messages: <SmsMessage>[]);

    await smsReaderService.saveApiCallHistoryEntry(
      otpCode: '554433',
      sender: 'Bank',
      smsReceivedAt: DateTime(2026, 1, 1, 14, 35),
      apiCalledAt: DateTime(2026, 1, 1, 14, 36),
      isSuccess: true,
      statusCode: 200,
    );
    await smsReaderService.saveApiCallHistoryEntry(
      otpCode: '112233',
      sender: 'Wallet',
      smsReceivedAt: DateTime(2026, 1, 1, 14, 37),
      apiCalledAt: DateTime(2026, 1, 1, 14, 38),
      isSuccess: false,
      errorMessage: 'API request failed (500).',
    );

    await tester.pumpWidget(
      MyApp(
        appConfig: _testAppConfig,
        smsReaderService: smsReaderService,
        otpApiService: FakeOtpApiService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-settings-button')));
    await tester.pumpAndSettle();

    for (var attempt = 0; attempt < 3; attempt += 1) {
      if (find.text('API history').evaluate().isNotEmpty) {
        break;
      }

      await tester.drag(
        find.byKey(const ValueKey('settings-page-list-view')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
    }

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('API history'), findsOneWidget);
    expect(find.text('Showing the latest 2 saved API calls.'), findsOneWidget);
    expect(find.text('OTP 112233 • Wallet'), findsOneWidget);
    expect(find.text('Error: API request failed (500).'), findsOneWidget);
    expect(find.text('OTP 554433 • Bank'), findsOneWidget);
    expect(find.text('Status code: 200'), findsOneWidget);
  });

  testWidgets(
    'refreshes again when a new SMS arrives during an in-flight load',
    (WidgetTester tester) async {
      final smsReaderService = FakeSmsReaderService(messages: <SmsMessage>[]);
      final firstReadCompleter = Completer<void>();
      var readCount = 0;

      await tester.pumpWidget(
        MyApp(
          appConfig: _testAppConfig,
          smsReaderService: smsReaderService,
          otpApiService: FakeOtpApiService(),
        ),
      );
      await tester.pumpAndSettle();

      smsReaderService.readAllMessagesHandler = () async {
        readCount += 1;
        if (readCount == 1) {
          await firstReadCompleter.future;
          return <SmsMessage>[];
        }

        return <SmsMessage>[
          SmsMessage(
            id: '55',
            sender: 'Bank',
            body: 'Your verification code is 550011.',
            receivedAt: DateTime(2026, 1, 1),
            type: 1,
          ),
        ];
      };

      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pump();

      smsReaderService.emitIncomingMessage();
      await tester.pump();

      firstReadCompleter.complete();
      await tester.pumpAndSettle();

      expect(find.text('Messages scanned: 1'), findsOneWidget);
      expect(find.text('OTP matches found: 1'), findsOneWidget);
      expect(find.text('550011'), findsOneWidget);
    },
  );

  testWidgets(
    'sends a queued realtime OTP after a non-realtime read marked it seen',
    (WidgetTester tester) async {
      final smsReaderService = FakeSmsReaderService(messages: <SmsMessage>[]);
      final otpApiService = FakeOtpApiService();
      final firstReadCompleter = Completer<void>();
      final receivedAt = DateTime(2026, 1, 1, 0, 3);
      var readCount = 0;

      await tester.pumpWidget(
        MyApp(
          appConfig: _testAutoHandleAppConfig,
          smsReaderService: smsReaderService,
          otpApiService: otpApiService,
        ),
      );
      await tester.pumpAndSettle();

      smsReaderService.readAllMessagesHandler = () async {
        readCount += 1;
        if (readCount == 1) {
          await firstReadCompleter.future;
        }

        return <SmsMessage>[
          SmsMessage(
            id: '61',
            sender: 'JX-VISATF-S',
            body:
                'OTP is 035221 for your verification on Visa2Fly. OTP is valid for 5 minutes only.',
            receivedAt: receivedAt,
            type: 1,
          ),
        ];
      };

      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pump();

      smsReaderService.emitIncomingMessage(<SmsMessage>[
        SmsMessage(
          id: 'foreground-61',
          sender: 'JX-VISATF-S',
          body:
              'OTP is 035221 for your verification on Visa2Fly. OTP is valid for 5 minutes only.',
          receivedAt: receivedAt,
          type: 1,
        ),
      ]);
      await tester.pump();

      firstReadCompleter.complete();
      await tester.pumpAndSettle();

      expect(otpApiService.sentOtps, <String>['035221']);
      expect(find.text('035221'), findsOneWidget);
    },
  );

  testWidgets('loads OTP matches automatically from pending background SMS', (
    WidgetTester tester,
  ) async {
    final otpApiService = FakeOtpApiService();

    await tester.pumpWidget(
      MyApp(
        appConfig: _testAutoHandleAppConfig,
        otpApiService: otpApiService,
        smsReaderService: FakeSmsReaderService(
          initialPendingBackgroundMessages: 1,
          messages: <SmsMessage>[
            SmsMessage(
              id: '31',
              sender: 'Bank',
              body: 'Your verification code is 553311.',
              receivedAt: DateTime(2026, 1, 1),
              type: 1,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Messages scanned: 1'), findsOneWidget);
    expect(find.text('OTP matches found: 1'), findsOneWidget);
    expect(find.text('553311'), findsOneWidget);
    expect(otpApiService.sentOtps, <String>['553311']);
  });

  testWidgets('does not resend an OTP that was already handled in background', (
    WidgetTester tester,
  ) async {
    final receivedAt = DateTime(2026, 1, 1);
    final smsReaderService = FakeSmsReaderService(
      initialPendingBackgroundMessages: 1,
      messages: <SmsMessage>[
        SmsMessage(
          id: '32',
          sender: 'Bank',
          body: 'Your verification code is 553311.',
          receivedAt: receivedAt,
          type: 1,
        ),
      ],
    );
    final otpApiService = FakeOtpApiService();

    smsReaderService.backgroundHandledOtpKeys.add(
      'bank|553311|${receivedAt.millisecondsSinceEpoch}',
    );

    await tester.pumpWidget(
      MyApp(
        appConfig: _testAutoHandleAppConfig,
        otpApiService: otpApiService,
        smsReaderService: smsReaderService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Messages scanned: 1'), findsOneWidget);
    expect(find.text('OTP matches found: 1'), findsOneWidget);
    expect(find.text('553311'), findsOneWidget);
    expect(otpApiService.sentOtps, isEmpty);
  });

  testWidgets('refreshes from pending background SMS when the app resumes', (
    WidgetTester tester,
  ) async {
    final smsReaderService = FakeSmsReaderService(messages: <SmsMessage>[]);
    final otpApiService = FakeOtpApiService();

    await tester.pumpWidget(
      MyApp(
        appConfig: _testAutoHandleAppConfig,
        smsReaderService: smsReaderService,
        otpApiService: otpApiService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Messages scanned: 0'), findsOneWidget);
    expect(find.text('OTP matches found: 0'), findsOneWidget);

    smsReaderService.messages = <SmsMessage>[
      SmsMessage(
        id: '41',
        sender: 'Bank',
        body: 'Use OTP 220044 to continue.',
        receivedAt: DateTime(2026, 1, 1),
        type: 1,
      ),
    ];
    smsReaderService.queueBackgroundMessage();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Messages scanned: 1'), findsOneWidget);
    expect(find.text('OTP matches found: 1'), findsOneWidget);
    expect(find.text('220044'), findsOneWidget);
    expect(otpApiService.sentOtps, <String>['220044']);
  });

  testWidgets('requests SMS permission from a dialog on refresh', (
    WidgetTester tester,
  ) async {
    final otpApiService = FakeOtpApiService();

    await tester.pumpWidget(
      MyApp(
        appConfig: _testAppConfig,
        otpApiService: otpApiService,
        smsReaderService: FakeSmsReaderService(initialPermission: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Grant SMS permission'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Allow SMS access?'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Messages scanned: 2'), findsOneWidget);
    expect(find.text('OTP matches found: 1'), findsOneWidget);
    expect(otpApiService.sentOtps, isEmpty);
  });

  testWidgets('truncates long message body and shows full text on tap', (
    WidgetTester tester,
  ) async {
    const longBody =
        'Your verification code is 482913. Use this code to complete sign in on your device before it expires in ten minutes.';

    await tester.pumpWidget(
      MyApp(
        appConfig: _testAppConfig,
        otpApiService: FakeOtpApiService(),
        smsReaderService: FakeSmsReaderService(
          messages: <SmsMessage>[
            SmsMessage(
              id: '99',
              sender: 'Bank',
              body: longBody,
              receivedAt: DateTime(2026, 1, 1),
              type: 1,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();

    final bodyText = tester.widget<Text>(
      find.byKey(const ValueKey('message-body-99')),
    );
    expect(bodyText.maxLines, 2);
    expect(bodyText.overflow, TextOverflow.ellipsis);

    await tester.ensureVisible(find.byKey(const ValueKey('message-body-99')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('message-body-99')));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    final sheetBodyText = tester.widget<Text>(
      find.byKey(const ValueKey('sheet-message-body-99')),
    );
    expect(sheetBodyText.data, longBody);
    expect(sheetBodyText.maxLines, isNull);
    expect(sheetBodyText.overflow, isNull);
  });

  testWidgets('shows received timing on the message card', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MyApp(
        appConfig: _testAppConfig,
        otpApiService: FakeOtpApiService(),
        smsReaderService: FakeSmsReaderService(
          messages: <SmsMessage>[
            SmsMessage(
              id: '77',
              sender: 'Bank',
              body: 'Your verification code is 482913.',
              receivedAt: DateTime(2026, 1, 1, 14, 35),
              type: 1,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(ListView));
    final localizations = MaterialLocalizations.of(context);
    final expectedLabel =
        'Received: ${localizations.formatMediumDate(DateTime(2026, 1, 1, 14, 35))}, '
        '${localizations.formatTimeOfDay(const TimeOfDay(hour: 14, minute: 35))}';

    final receivedText = tester.widget<Text>(
      find.byKey(const ValueKey('message-received-77')),
    );
    expect(receivedText.data, isNotNull);
    expect(receivedText.data, expectedLabel);
  });

  testWidgets('applies sender filters from code config', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MyApp(
        appConfig: const AppConfig(
          apiBaseUrl: 'https://example.com/api',
          senderFilters: <String>['8123'],
        ),
        otpApiService: FakeOtpApiService(),
        smsReaderService: FakeSmsReaderService(
          messages: <SmsMessage>[
            SmsMessage(
              id: '1',
              sender: 'Bank',
              body: 'Your verification code is 482913.',
              receivedAt: DateTime(2026, 1, 1),
              type: 1,
            ),
            SmsMessage(
              id: '2',
              sender: '+66 8123 4567',
              body: 'Your login code is 774411.',
              receivedAt: DateTime(2026, 1, 1),
              type: 1,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();

    expect(find.text('Messages scanned: 2'), findsOneWidget);
    expect(find.text('OTP matches found: 1'), findsOneWidget);
    expect(find.text('774411'), findsOneWidget);
    expect(find.text('482913'), findsNothing);
    expect(
      find.text('No OTP messages matched the current filters.'),
      findsNothing,
    );
  });
}
