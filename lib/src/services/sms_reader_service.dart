import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app_logger.dart';
import '../config/app_config.dart';
import '../models/api_call_history_entry.dart';
import '../models/sms_message.dart';

class SmsReaderService {
  const SmsReaderService();

  static const MethodChannel _channel = MethodChannel(
    'otp_message_reader/sms_reader',
  );
  static const EventChannel _eventsChannel = EventChannel(
    'otp_message_reader/sms_events',
  );

  bool get supportsSmsReading =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> hasSmsPermission() async {
    if (!supportsSmsReading) {
      AppLogger.warn(
        'SmsReaderService',
        'Skipped SMS permission check because SMS reading is unsupported.',
      );
      return false;
    }

    final hasPermission = await _channel.invokeMethod<bool>('hasSmsPermission') ?? false;
    AppLogger.info(
      'SmsReaderService',
      'Checked SMS permission.',
      data: <String, Object?>{'hasPermission': hasPermission},
    );
    return hasPermission;
  }

  Future<bool> requestSmsPermission() async {
    if (!supportsSmsReading) {
      AppLogger.warn(
        'SmsReaderService',
        'Skipped SMS permission request because SMS reading is unsupported.',
      );
      return false;
    }

    AppLogger.info('SmsReaderService', 'Requesting SMS permission from native bridge.');
    final granted =
        await _channel.invokeMethod<bool>('requestSmsPermission') ?? false;
    AppLogger.info(
      'SmsReaderService',
      'Completed SMS permission request.',
      data: <String, Object?>{'granted': granted},
    );
    return granted;
  }

  Future<void> ensureNotificationPermission() async {
    if (!supportsSmsReading) {
      AppLogger.warn(
        'SmsReaderService',
        'Skipped notification permission check because SMS reading is unsupported.',
      );
      return;
    }

    try {
      AppLogger.info(
        'SmsReaderService',
        'Ensuring notification permission through native bridge.',
      );
      await _channel.invokeMethod<void>('ensureNotificationPermission');
    } on MissingPluginException {
      AppLogger.warn(
        'SmsReaderService',
        'Notification permission handling is unavailable on the current runtime. '
            'Restart the app after native changes to enable it.',
      );
    }
  }

  Future<void> syncBackgroundApiConfig(AppConfig appConfig) async {
    if (!supportsSmsReading) {
      AppLogger.warn(
        'SmsReaderService',
        'Skipped background API config sync because SMS reading is unsupported.',
      );
      return;
    }

    try {
      AppLogger.info(
        'SmsReaderService',
        'Syncing background API config through native bridge.',
        data: <String, Object?>{
          'apiBaseUrl': appConfig.apiBaseUrl,
          'senderFilters': appConfig.senderFilters,
        },
      );
      await _channel.invokeMethod<void>('syncBackgroundApiConfig', <String, Object?>{
        'apiBaseUrl': appConfig.apiBaseUrl,
        'apiOrigin': appConfig.apiOrigin,
        'apiReferer': appConfig.apiReferer,
        'visaClientHeaderValue': appConfig.visaClientHeaderValue,
        'senderFilters': appConfig.senderFilters,
      });
    } on MissingPluginException {
      AppLogger.warn(
        'SmsReaderService',
        'Background API config sync is unavailable on the current runtime. '
            'Restart the app after native changes to enable it.',
      );
    }
  }

  Future<void> showApiSuccessNotification({
    required String otpCode,
    required String sender,
    required String receivedAtLabel,
  }) async {
    if (
        !supportsSmsReading ||
        otpCode.trim().isEmpty ||
        sender.trim().isEmpty ||
        receivedAtLabel.trim().isEmpty) {
      AppLogger.warn(
        'SmsReaderService',
        'Skipped API success notification request because the payload was incomplete.',
        data: <String, Object?>{
          'otpCode': otpCode,
          'sender': sender,
          'receivedAtLabel': receivedAtLabel,
          'supportsSmsReading': supportsSmsReading,
        },
      );
      return;
    }

    try {
      AppLogger.info(
        'SmsReaderService',
        'Sending API success notification request to native bridge.',
        data: <String, Object?>{
          'otpCode': otpCode,
          'sender': sender,
        },
      );
      await _channel.invokeMethod<void>('showApiSuccessNotification', <String, Object?>{
        'otpCode': otpCode,
        'sender': sender,
        'receivedAtLabel': receivedAtLabel,
      });
      AppLogger.info(
        'SmsReaderService',
        'Native API success notification request completed.',
        data: <String, Object?>{'otpCode': otpCode},
      );
    } on PlatformException catch (error) {
      AppLogger.warn(
        'SmsReaderService',
        'API success notification bridge failed.',
        data: <String, Object?>{
          'otpCode': otpCode,
          'reason': error.message ?? error.code,
        },
      );
    } on MissingPluginException {
      AppLogger.warn(
        'SmsReaderService',
        'API success notifications are unavailable on the current runtime. '
            'Restart the app after native changes to enable them.',
      );
    }
  }

  Future<void> saveApiCallHistoryEntry({
    required String otpCode,
    required String sender,
    required DateTime smsReceivedAt,
    required DateTime apiCalledAt,
    required bool isSuccess,
    int? statusCode,
    String? errorMessage,
  }) async {
    if (!supportsSmsReading || otpCode.trim().isEmpty || sender.trim().isEmpty) {
      AppLogger.warn(
        'SmsReaderService',
        'Skipped API history save because the payload was incomplete.',
        data: <String, Object?>{
          'otpCode': otpCode,
          'sender': sender,
          'supportsSmsReading': supportsSmsReading,
        },
      );
      return;
    }

    try {
      final trimmedErrorMessage = errorMessage?.trim();

      AppLogger.info(
        'SmsReaderService',
        'Saving API call history entry through native bridge.',
        data: <String, Object?>{
          'otpCode': otpCode,
          'isSuccess': isSuccess,
          'statusCode': statusCode,
        },
      );

      await _channel.invokeMethod<void>('appendApiCallHistoryEntry', <String, Object?>{
        'otpCode': otpCode,
        'sender': sender,
        'smsReceivedAtMillis': smsReceivedAt.millisecondsSinceEpoch,
        'apiCalledAtMillis': apiCalledAt.millisecondsSinceEpoch,
        'isSuccess': isSuccess,
        if (statusCode case final int value) 'statusCode': value,
        if (trimmedErrorMessage case final String value) 'errorMessage': value,
      });
      AppLogger.info(
        'SmsReaderService',
        'API call history entry saved through native bridge.',
        data: <String, Object?>{
          'otpCode': otpCode,
          'isSuccess': isSuccess,
        },
      );
    } on PlatformException catch (error) {
      AppLogger.warn(
        'SmsReaderService',
        'API call history storage bridge failed.',
        data: <String, Object?>{
          'otpCode': otpCode,
          'reason': error.message ?? error.code,
        },
      );
    } on MissingPluginException {
      AppLogger.warn(
        'SmsReaderService',
        'API call history storage is unavailable on the current runtime. '
            'Restart the app after native changes to enable it.',
      );
    }
  }

  Future<List<ApiCallHistoryEntry>> getApiCallHistory() async {
    if (!supportsSmsReading) {
      AppLogger.warn(
        'SmsReaderService',
        'Skipped API history read because SMS reading is unsupported.',
      );
      return const <ApiCallHistoryEntry>[];
    }

    try {
      AppLogger.info('SmsReaderService', 'Reading API call history from native bridge.');
      final rawEntries =
          await _channel.invokeListMethod<dynamic>('getApiCallHistory') ?? const <dynamic>[];

      final entries = rawEntries
          .map((dynamic rawEntry) {
            return ApiCallHistoryEntry.fromMap(
              Map<Object?, Object?>.from(rawEntry as Map),
            );
          })
          .toList(growable: false);
      AppLogger.info(
        'SmsReaderService',
        'Loaded API call history from native bridge.',
        data: <String, Object?>{'count': entries.length},
      );
      return entries;
    } on MissingPluginException {
      AppLogger.warn(
        'SmsReaderService',
        'API call history is unavailable on the current runtime. '
            'Restart the app after native changes to enable it.',
      );
      return const <ApiCallHistoryEntry>[];
    }
  }

  Future<int> consumePendingBackgroundMessages() async {
    if (!supportsSmsReading) {
      AppLogger.warn(
        'SmsReaderService',
        'Skipped pending background message check because SMS reading is unsupported.',
      );
      return 0;
    }

    try {
      final pendingMessages =
          await _channel.invokeMethod<int>('consumePendingBackgroundMessages') ?? 0;
      AppLogger.info(
        'SmsReaderService',
        'Consumed pending background messages.',
        data: <String, Object?>{'count': pendingMessages},
      );
      return pendingMessages;
    } on MissingPluginException {
      AppLogger.warn(
        'SmsReaderService',
        'Background SMS handling is unavailable on the current runtime. '
            'Restart the app after native changes to enable it.',
      );
      return 0;
    }
  }

  Future<List<String>> consumeBackgroundHandledOtpKeys() async {
    if (!supportsSmsReading) {
      AppLogger.warn(
        'SmsReaderService',
        'Skipped background handled OTP key check because SMS reading is unsupported.',
      );
      return const <String>[];
    }

    try {
      final handledKeys =
          await _channel.invokeListMethod<String>('consumeBackgroundHandledOtpKeys') ??
          const <String>[];
      AppLogger.info(
        'SmsReaderService',
        'Consumed background handled OTP keys.',
        data: <String, Object?>{'count': handledKeys.length},
      );
      return handledKeys;
    } on MissingPluginException {
      AppLogger.warn(
        'SmsReaderService',
        'Background handled OTP key storage is unavailable on the current runtime. '
            'Restart the app after native changes to enable it.',
      );
      return const <String>[];
    }
  }

  Stream<List<SmsMessage>> watchIncomingMessages() {
    if (!supportsSmsReading) {
      AppLogger.warn(
        'SmsReaderService',
        'Skipped realtime SMS event subscription because SMS reading is unsupported.',
      );
      return const Stream<List<SmsMessage>>.empty();
    }

    return Stream<List<SmsMessage>>.multi((controller) {
      AppLogger.info('SmsReaderService', 'Listening for realtime SMS events.');
      final subscription = _eventsChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          final incomingMessages = _parseIncomingMessagesEvent(event);
          AppLogger.info(
            'SmsReaderService',
            'Received realtime SMS event.',
            data: <String, Object?>{
              'messageCount': incomingMessages.length,
              'hasPayload': incomingMessages.isNotEmpty,
            },
          );
          controller.add(incomingMessages);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (error is MissingPluginException) {
            AppLogger.warn(
              'SmsReaderService',
              'Realtime SMS events are unavailable on the current runtime. '
                  'Do a full stop and run again after native changes to enable them.',
            );
            controller.close();
            return;
          }

          AppLogger.error(
            'SmsReaderService',
            'Realtime SMS event stream emitted an error.',
            error: error,
            stackTrace: stackTrace,
          );
          controller.addError(error, stackTrace);
        },
        onDone: controller.close,
      );

      controller.onCancel = () {
        AppLogger.info('SmsReaderService', 'Stopped listening for realtime SMS events.');
        return subscription.cancel();
      };
    });
  }

  List<SmsMessage> _parseIncomingMessagesEvent(dynamic event) {
    if (event is Map) {
      return <SmsMessage>[SmsMessage.fromMap(Map<Object?, Object?>.from(event))];
    }

    if (event is! List) {
      return const <SmsMessage>[];
    }

    return event
        .whereType<Map>()
        .map((rawMessage) => SmsMessage.fromMap(Map<Object?, Object?>.from(rawMessage)))
        .toList(growable: false);
  }

  Future<List<SmsMessage>> readAllMessages() async {
    if (!supportsSmsReading) {
      AppLogger.warn(
        'SmsReaderService',
        'SMS read was requested on an unsupported platform.',
      );
      throw UnsupportedError('SMS reading is available only on Android.');
    }

    AppLogger.info('SmsReaderService', 'Reading all SMS messages from native bridge.');
    final rawMessages =
        await _channel.invokeListMethod<dynamic>('readAllMessages') ??
        const <dynamic>[];

    final messages = rawMessages
        .map((dynamic rawMessage) {
          return SmsMessage.fromMap(Map<Object?, Object?>.from(rawMessage as Map));
        })
        .toList(growable: false);
    AppLogger.info(
      'SmsReaderService',
      'Read SMS messages from native bridge.',
      data: <String, Object?>{'count': messages.length},
    );
    return messages;
  }
}