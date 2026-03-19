import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_logger.dart';
import '../config/app_config.dart';
import '../models/otp_match.dart';
import '../models/sms_message.dart';
import 'api_history_page.dart';
import '../services/otp_api_service.dart';
import '../services/otp_message_filter.dart';
import '../services/sms_reader_service.dart';
import '../theme/app_theme.dart';
import '../widgets/message_body_sheet.dart';
import '../widgets/otp_message_tile.dart';
import '../widgets/panel_card.dart';
import '../widgets/reader_intro_card.dart';
import '../widgets/reader_status_card.dart';

class OtpReaderPage extends StatefulWidget {
  const OtpReaderPage({
    super.key,
    required this.smsReaderService,
    required this.otpApiService,
    required this.otpMessageFilter,
    required this.appConfig,
  });

  final SmsReaderService smsReaderService;
  final OtpApiService otpApiService;
  final OtpMessageFilter otpMessageFilter;
  final AppConfig appConfig;

  @override
  State<OtpReaderPage> createState() => _OtpReaderPageState();
}

class _OtpReaderPageState extends State<OtpReaderPage>
    with WidgetsBindingObserver {
  bool _hasPermission = false;
  bool _isLoading = false;
  bool _pendingIncomingRefresh = false;
  String? _errorMessage;
  int _totalMessagesRead = 0;
  List<OtpMatch> _otpMatches = const <OtpMatch>[];
  final Set<String> _attemptedOtpMessageIds = <String>{};
  final Set<String> _backgroundHandledOtpMatchKeys = <String>{};
  final Set<String> _foregroundHandledIncomingOtpEventKeys = <String>{};
  final Set<String> _manualSendInProgressMessageIds = <String>{};
  final List<SmsMessage> _queuedIncomingMessages = <SmsMessage>[];
  StreamSubscription<List<SmsMessage>>? _incomingMessagesSubscription;

  @override
  void initState() {
    super.initState();
    AppLogger.info(
      'OtpReaderPage',
      'Initializing OTP reader page.',
      data: <String, Object?>{
        'apiBaseUrl': widget.appConfig.apiBaseUrl,
        'senderFilters': widget.appConfig.senderFilters,
      },
    );
    unawaited(widget.smsReaderService.syncBackgroundApiConfig(widget.appConfig));
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPermissionStatus();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppLogger.info('OtpReaderPage', 'App resumed. Checking pending background SMS.');
      unawaited(_checkForPendingBackgroundMessages());
    }
  }

  @override
  void dispose() {
    AppLogger.info('OtpReaderPage', 'Disposing OTP reader page.');
    WidgetsBinding.instance.removeObserver(this);
    _incomingMessagesSubscription?.cancel();
    super.dispose();
  }

  bool get _hasSenderFilters => widget.appConfig.senderFilters.isNotEmpty;

  String get _helperText => _hasPermission
      ? 'Pull down to refresh and load OTP messages.'
      : 'Pull down to load OTP messages.';

  String get _emptyStateText {
    if (_totalMessagesRead == 0) {
      return 'No OTP messages loaded yet.';
    }

    if (!_hasSenderFilters) {
      return 'No OTP messages found.';
    }

    return 'No OTP messages matched the current filters.';
  }

  Future<void> _loadPermissionStatus() async {
    if (!widget.smsReaderService.supportsSmsReading) {
      AppLogger.warn(
        'OtpReaderPage',
        'Skipping permission load because SMS reading is unsupported.',
      );
      return;
    }

    AppLogger.info('OtpReaderPage', 'Loading SMS permission status.');

    final hasPermission = await widget.smsReaderService.hasSmsPermission();
    if (!mounted) {
      return;
    }

    AppLogger.info(
      'OtpReaderPage',
      'Loaded SMS permission status.',
      data: <String, Object?>{'hasPermission': hasPermission},
    );

    setState(() {
      _hasPermission = hasPermission;
    });

    if (hasPermission) {
      unawaited(widget.smsReaderService.ensureNotificationPermission());
    }

    _updateIncomingMessagesSubscription();

    if (hasPermission) {
      final loadedFromPendingBackground = await _checkForPendingBackgroundMessages();
      if (!mounted || loadedFromPendingBackground) {
        return;
      }

      await _readOtpMessages();
    }
  }

  Future<void> _requestPermission() async {
    AppLogger.info('OtpReaderPage', 'Requesting SMS permission from the user.');
    setState(() {
      _errorMessage = null;
    });

    final granted = await widget.smsReaderService.requestSmsPermission();
    if (!mounted) {
      return;
    }

    setState(() {
      _hasPermission = granted;
      if (!granted) {
        _errorMessage = 'SMS permission was not granted.';
      }
    });

    AppLogger.info(
      'OtpReaderPage',
      'SMS permission request completed.',
      data: <String, Object?>{'granted': granted},
    );

    if (granted) {
      unawaited(widget.smsReaderService.ensureNotificationPermission());
    } else {
      AppLogger.warn('OtpReaderPage', 'SMS permission was denied by the user.');
    }

    _updateIncomingMessagesSubscription();
  }

  void _updateIncomingMessagesSubscription() {
    final shouldListen = widget.smsReaderService.supportsSmsReading && _hasPermission;

    if (!shouldListen) {
      AppLogger.info(
        'OtpReaderPage',
        'Stopping incoming SMS listener.',
        data: <String, Object?>{'hasPermission': _hasPermission},
      );
      _incomingMessagesSubscription?.cancel();
      _incomingMessagesSubscription = null;
      return;
    }

    if (_incomingMessagesSubscription != null) {
      AppLogger.info('OtpReaderPage', 'Incoming SMS listener is already active.');
      return;
    }

    AppLogger.info('OtpReaderPage', 'Starting incoming SMS listener.');

    _incomingMessagesSubscription = widget.smsReaderService
        .watchIncomingMessages()
        .listen((incomingMessages) {
          if (!mounted) {
            return;
          }

          AppLogger.info(
            'OtpReaderPage',
            'Incoming SMS event received. Refreshing inbox.',
            data: <String, Object?>{'incomingMessages': incomingMessages.length},
          );
          unawaited(_refreshForIncomingMessages(incomingMessages: incomingMessages));
        }, onError: (Object error, StackTrace stackTrace) {
          if (error is MissingPluginException) {
            AppLogger.warn(
              'OtpReaderPage',
              'Incoming SMS listener stopped because the native stream is unavailable.',
            );
            _incomingMessagesSubscription?.cancel();
            _incomingMessagesSubscription = null;
            return;
          }

          AppLogger.error(
            'OtpReaderPage',
            'Incoming SMS listener emitted an error.',
            error: error,
            stackTrace: stackTrace,
          );

          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'otp_message_reader',
              context: ErrorDescription('while listening for incoming SMS events'),
            ),
          );
        });
  }

  Future<void> _refreshForIncomingMessages({
    List<SmsMessage> incomingMessages = const <SmsMessage>[],
  }) async {
    if (!mounted || !widget.smsReaderService.supportsSmsReading || !_hasPermission) {
      AppLogger.warn(
        'OtpReaderPage',
        'Skipped refresh for incoming messages because requirements were not met.',
        data: <String, Object?>{
          'mounted': mounted,
          'supportsSmsReading': widget.smsReaderService.supportsSmsReading,
          'hasPermission': _hasPermission,
        },
      );
      return;
    }

    if (_isLoading) {
      _pendingIncomingRefresh = true;
      _queuedIncomingMessages.addAll(incomingMessages);
      AppLogger.info(
        'OtpReaderPage',
        'Queued an incoming-message refresh because a read is already in progress.',
        data: <String, Object?>{'queuedIncomingMessages': _queuedIncomingMessages.length},
      );
      return;
    }

    final incomingMessagesForSync = <SmsMessage>[
      ..._queuedIncomingMessages,
      ...incomingMessages,
    ];
    _queuedIncomingMessages.clear();

    AppLogger.info(
      'OtpReaderPage',
      'Refreshing OTP messages for incoming SMS.',
      data: <String, Object?>{'incomingMessages': incomingMessagesForSync.length},
    );

    await _readOtpMessages(
      syncNewOtpMatches: true,
      incomingMessagesForSync: incomingMessagesForSync,
    );
  }

  Future<bool> _checkForPendingBackgroundMessages() async {
    if (!widget.smsReaderService.supportsSmsReading || !_hasPermission || _isLoading) {
      AppLogger.info(
        'OtpReaderPage',
        'Skipped pending background SMS check.',
        data: <String, Object?>{
          'supportsSmsReading': widget.smsReaderService.supportsSmsReading,
          'hasPermission': _hasPermission,
          'isLoading': _isLoading,
        },
      );
      return false;
    }

    await _consumeBackgroundHandledOtpKeys();

    final pendingMessages =
        await widget.smsReaderService.consumePendingBackgroundMessages();
    AppLogger.info(
      'OtpReaderPage',
      'Checked pending background SMS count.',
      data: <String, Object?>{'pendingMessages': pendingMessages},
    );
    if (!mounted || pendingMessages <= 0 || _isLoading) {
      return false;
    }

    AppLogger.info(
      'OtpReaderPage',
      'Found pending background SMS. Triggering refresh.',
      data: <String, Object?>{'pendingMessages': pendingMessages},
    );
    await _refreshForIncomingMessages();
    return true;
  }

  String _otpMatchSessionKey(OtpMatch match) =>
      '${match.message.sender.trim().toLowerCase()}|'
      '${match.otpCode}|'
      '${match.message.receivedAt.millisecondsSinceEpoch}';

  String _incomingOtpEventKey(OtpMatch match) =>
      '${match.message.sender.trim().toLowerCase()}|'
      '${match.otpCode}|'
      '${match.message.receivedAt.millisecondsSinceEpoch}|'
      '${match.message.body.trim()}';

  bool _sameIncomingMessage(SmsMessage left, SmsMessage right) =>
      left.sender.trim().toLowerCase() == right.sender.trim().toLowerCase() &&
      left.receivedAt.millisecondsSinceEpoch == right.receivedAt.millisecondsSinceEpoch &&
      left.body.trim() == right.body.trim();

  Future<void> _consumeBackgroundHandledOtpKeys() async {
    final handledKeys = await widget.smsReaderService.consumeBackgroundHandledOtpKeys();
    if (handledKeys.isEmpty) {
      return;
    }

    _backgroundHandledOtpMatchKeys.addAll(
      handledKeys.map((key) => key.trim()).where((key) => key.isNotEmpty),
    );
    AppLogger.info(
      'OtpReaderPage',
      'Recorded background-handled OTP keys for this app session.',
      data: <String, Object?>{
        'newlyHandledKeys': handledKeys.length,
        'handledKeyCount': _backgroundHandledOtpMatchKeys.length,
      },
    );
  }

  void _recordOtpMatchesAsSeen(Iterable<OtpMatch> matches) {
    final newMatches = matches.toList(growable: false);
    if (newMatches.isEmpty) {
      return;
    }

    _attemptedOtpMessageIds.addAll(newMatches.map((match) => match.message.id));
    AppLogger.info(
      'OtpReaderPage',
      'Recorded OTP matches as seen for this app session.',
      data: <String, Object?>{
        'newlySeen': newMatches.length,
        'attemptedMessageIdCount': _attemptedOtpMessageIds.length,
        'backgroundHandledKeyCount': _backgroundHandledOtpMatchKeys.length,
      },
    );
  }

  void _recordForegroundHandledIncomingOtpEventKeys(Iterable<String> keys) {
    final normalizedKeys = keys.map((key) => key.trim()).where((key) => key.isNotEmpty).toSet();
    if (normalizedKeys.isEmpty) {
      return;
    }

    _foregroundHandledIncomingOtpEventKeys.addAll(normalizedKeys);
    AppLogger.info(
      'OtpReaderPage',
      'Recorded foreground-handled incoming OTP event keys for this app session.',
      data: <String, Object?>{
        'newlyHandledKeys': normalizedKeys.length,
        'handledKeyCount': _foregroundHandledIncomingOtpEventKeys.length,
      },
    );
  }

  Future<void> _showApiSuccessNotification(OtpMatch match) async {
    final localizations = MaterialLocalizations.of(context);
    final receivedAt = match.message.receivedAt;
    final receivedAtLabel =
        '${localizations.formatMediumDate(receivedAt)}, '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(receivedAt))}';

    try {
      AppLogger.info(
        'OtpReaderPage',
        'Showing API success notification.',
        data: <String, Object?>{
          'otpCode': match.otpCode,
          'sender': match.message.sender,
        },
      );
      await widget.smsReaderService.showApiSuccessNotification(
        otpCode: match.otpCode,
        sender: match.message.sender,
        receivedAtLabel: receivedAtLabel,
      );
      AppLogger.info(
        'OtpReaderPage',
        'API success notification request completed.',
        data: <String, Object?>{'otpCode': match.otpCode},
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'OtpReaderPage',
        'Failed to show OTP API success notification.',
        error: error,
        stackTrace: stackTrace,
        data: <String, Object?>{'otpCode': match.otpCode},
      );
    }
  }

  Future<void> _saveApiCallHistoryEntrySafely({
    required String otpCode,
    required String sender,
    required DateTime smsReceivedAt,
    required DateTime apiCalledAt,
    required bool isSuccess,
    int? statusCode,
    String? errorMessage,
  }) async {
    try {
      await widget.smsReaderService.saveApiCallHistoryEntry(
        otpCode: otpCode,
        sender: sender,
        smsReceivedAt: smsReceivedAt,
        apiCalledAt: apiCalledAt,
        isSuccess: isSuccess,
        statusCode: statusCode,
        errorMessage: errorMessage,
      );
      AppLogger.info(
        'OtpReaderPage',
        'Saved OTP API call history entry.',
        data: <String, Object?>{
          'otpCode': otpCode,
          'sender': sender,
          'isSuccess': isSuccess,
          'statusCode': statusCode,
        },
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'OtpReaderPage',
        'Failed to save OTP API call history.',
        error: error,
        stackTrace: stackTrace,
        data: <String, Object?>{
          'otpCode': otpCode,
          'sender': sender,
          'isSuccess': isSuccess,
        },
      );
    }
  }

  Future<_OtpApiSyncResult> _sendOtpMatchesToApi(List<OtpMatch> matches) async {
    if (matches.isEmpty) {
      AppLogger.info('OtpReaderPage', 'No OTP matches to send to the API.');
      return const _OtpApiSyncResult();
    }

    AppLogger.info(
      'OtpReaderPage',
      'Sending OTP matches to the API.',
      data: <String, Object?>{
        'count': matches.length,
        'matches': matches
            .take(5)
            .map((match) => '${match.message.sender}:${match.otpCode}')
            .toList(growable: false),
      },
    );

    final successfulMatches = <OtpMatch>[];
    String? firstErrorMessage;

    for (final match in matches) {
      try {
        AppLogger.info(
          'OtpReaderPage',
          'Sending OTP match to API.',
          data: <String, Object?>{
            'otpCode': match.otpCode,
            'sender': match.message.sender,
            'receivedAt': match.message.receivedAt,
          },
        );
        final response = await widget.otpApiService.sendLatestOtp(
          match.otpCode,
          appConfig: widget.appConfig,
        );

        await _saveApiCallHistoryEntrySafely(
          otpCode: match.otpCode,
          sender: match.message.sender,
          smsReceivedAt: match.message.receivedAt,
          apiCalledAt: DateTime.now(),
          isSuccess: response.isSuccess,
          statusCode: response.statusCode,
        );

        AppLogger.info(
          'OtpReaderPage',
          'OTP API call completed successfully.',
          data: <String, Object?>{
            'otpCode': match.otpCode,
            'statusCode': response.statusCode,
          },
        );

        if (response.isSuccess) {
          successfulMatches.add(match);
        }
      } on OtpApiException catch (error) {
        await _saveApiCallHistoryEntrySafely(
          otpCode: match.otpCode,
          sender: match.message.sender,
          smsReceivedAt: match.message.receivedAt,
          apiCalledAt: DateTime.now(),
          isSuccess: false,
          errorMessage: error.message,
        );
        AppLogger.warn(
          'OtpReaderPage',
          'OTP API call failed with a handled API error.',
          data: <String, Object?>{
            'otpCode': match.otpCode,
            'sender': match.message.sender,
            'reason': error.message,
          },
        );
        firstErrorMessage ??= 'Could not send OTP ${match.otpCode} to API: ${error.message}';
      } catch (error, stackTrace) {
        await _saveApiCallHistoryEntrySafely(
          otpCode: match.otpCode,
          sender: match.message.sender,
          smsReceivedAt: match.message.receivedAt,
          apiCalledAt: DateTime.now(),
          isSuccess: false,
          errorMessage: error.toString(),
        );
        AppLogger.error(
          'OtpReaderPage',
          'OTP API call failed with an unexpected error.',
          error: error,
          stackTrace: stackTrace,
          data: <String, Object?>{
            'otpCode': match.otpCode,
            'sender': match.message.sender,
          },
        );
        firstErrorMessage ??= 'Could not send OTP ${match.otpCode} to API: $error';
      }
    }

    AppLogger.info(
      'OtpReaderPage',
      'Finished sending OTP matches to the API.',
      data: <String, Object?>{
        'attempted': matches.length,
        'successful': successfulMatches.length,
        'hasErrorMessage': firstErrorMessage != null,
      },
    );

    return _OtpApiSyncResult(
      successfulMatches: successfulMatches,
      errorMessage: firstErrorMessage,
    );
  }

  Future<void> _sendOtpMatchManually(OtpMatch match) async {
    if (_isLoading) {
      AppLogger.warn(
        'OtpReaderPage',
        'Skipped manual OTP API send because an inbox read is already in progress.',
        data: <String, Object?>{'otpCode': match.otpCode, 'sender': match.message.sender},
      );
      return;
    }

    if (_manualSendInProgressMessageIds.contains(match.message.id)) {
      AppLogger.info(
        'OtpReaderPage',
        'Skipped manual OTP API send because the same message is already being sent.',
        data: <String, Object?>{'otpCode': match.otpCode, 'sender': match.message.sender},
      );
      return;
    }

    AppLogger.info(
      'OtpReaderPage',
      'Manual OTP API send requested from a message tile.',
      data: <String, Object?>{
        'otpCode': match.otpCode,
        'sender': match.message.sender,
        'messageId': match.message.id,
      },
    );

    setState(() {
      _manualSendInProgressMessageIds.add(match.message.id);
      _errorMessage = null;
    });

    try {
      final apiSyncResult = await _sendOtpMatchesToApi(<OtpMatch>[match]);
      if (!mounted) {
        return;
      }

      for (final successfulMatch in apiSyncResult.successfulMatches) {
        await _showApiSuccessNotification(successfulMatch);
        if (!mounted) {
          return;
        }
      }

      if (apiSyncResult.errorMessage != null) {
        setState(() {
          _errorMessage = apiSyncResult.errorMessage;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _manualSendInProgressMessageIds.remove(match.message.id);
        });
      }
    }
  }

  OtpMatch _latestOtpMatch(Iterable<OtpMatch> matches) {
    final iterator = matches.iterator;
    iterator.moveNext();
    var latestMatch = iterator.current;
    while (iterator.moveNext()) {
      if (!iterator.current.message.receivedAt.isBefore(latestMatch.message.receivedAt)) {
        latestMatch = iterator.current;
      }
    }
    return latestMatch;
  }

  OtpMatch _resolveIncomingOtpMatch(List<OtpMatch> matches, OtpMatch incomingMatch) {
    for (final match in matches) {
      if (_sameIncomingMessage(match.message, incomingMatch.message)) {
        return match;
      }
    }

    final incomingSessionKey = _otpMatchSessionKey(incomingMatch);
    for (final match in matches) {
      if (_otpMatchSessionKey(match) == incomingSessionKey) {
        return match;
      }
    }

    return incomingMatch;
  }

  _RealtimeOtpSelection _selectRealtimeOtpMatchesToSync(
    List<OtpMatch> matches,
    List<OtpMatch> newOtpMatches, {
    required bool syncNewOtpMatches,
    List<SmsMessage> incomingMessagesForSync = const <SmsMessage>[],
  }) {
    if (!syncNewOtpMatches) {
      return const _RealtimeOtpSelection();
    }

    final incomingMatchesByKey = <String, OtpMatch>{};
    for (final incomingMessage in incomingMessagesForSync) {
      final incomingMatch = widget.otpMessageFilter.matchMessage(
        incomingMessage,
        senderFilters: widget.appConfig.senderFilters,
      );
      if (incomingMatch == null) {
        continue;
      }

      final resolvedMatch = _resolveIncomingOtpMatch(matches, incomingMatch);
      if (_backgroundHandledOtpMatchKeys.contains(_otpMatchSessionKey(resolvedMatch))) {
        continue;
      }

      final eventKey = _incomingOtpEventKey(resolvedMatch);
      if (_foregroundHandledIncomingOtpEventKeys.contains(eventKey)) {
        continue;
      }

      incomingMatchesByKey[eventKey] = resolvedMatch;
    }

    if (incomingMatchesByKey.isNotEmpty) {
      final latestMatch = _latestOtpMatch(incomingMatchesByKey.values);
      final eventKey = _incomingOtpEventKey(latestMatch);
      AppLogger.info(
        'OtpReaderPage',
        'Selected the latest realtime OTP match for API sync.',
        data: <String, Object?>{
          'availableRealtimeMatches': incomingMatchesByKey.length,
          'selectedOtpCode': latestMatch.otpCode,
          'selectedSender': latestMatch.message.sender,
          'selectedReceivedAt': latestMatch.message.receivedAt,
          'selectionSource': 'incomingPayload',
        },
      );

      return _RealtimeOtpSelection(
        matchesToSync: <OtpMatch>[latestMatch],
        incomingOtpEventKeys: <String>[eventKey],
      );
    }

    if (newOtpMatches.isEmpty) {
      return const _RealtimeOtpSelection();
    }

    final latestMatch = _latestOtpMatch(newOtpMatches);

    AppLogger.info(
      'OtpReaderPage',
      'Selected the latest realtime OTP match for API sync.',
      data: <String, Object?>{
        'availableRealtimeMatches': newOtpMatches.length,
        'selectedOtpCode': latestMatch.otpCode,
        'selectedSender': latestMatch.message.sender,
        'selectedReceivedAt': latestMatch.message.receivedAt,
        'selectionSource': 'inboxRead',
      },
    );

    return _RealtimeOtpSelection(matchesToSync: <OtpMatch>[latestMatch]);
  }

  Future<void> _readOtpMessages({
    bool syncNewOtpMatches = false,
    List<SmsMessage> incomingMessagesForSync = const <SmsMessage>[],
  }) async {
    if (_isLoading) {
      AppLogger.info(
        'OtpReaderPage',
        'Skipped OTP read because another read is already in progress.',
        data: <String, Object?>{'syncNewOtpMatches': syncNewOtpMatches},
      );
      return;
    }

    AppLogger.info(
      'OtpReaderPage',
      'Starting OTP inbox read.',
      data: <String, Object?>{
        'syncNewOtpMatches': syncNewOtpMatches,
          'incomingMessagesForSync': incomingMessagesForSync.length,
        'senderFilters': widget.appConfig.senderFilters,
        'existingMatchCount': _otpMatches.length,
        'attemptedMessageCount': _attemptedOtpMessageIds.length,
        'backgroundHandledKeyCount': _backgroundHandledOtpMatchKeys.length,
      },
    );

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final messages = await widget.smsReaderService.readAllMessages();
      final matches = widget.otpMessageFilter.filterMessages(
        messages,
        senderFilters: widget.appConfig.senderFilters,
      );
      if (!mounted) {
        return;
      }

      final newOtpMatches = matches
          .where(
            (match) =>
                !_attemptedOtpMessageIds.contains(match.message.id) &&
                !_backgroundHandledOtpMatchKeys.contains(_otpMatchSessionKey(match)) &&
                !_foregroundHandledIncomingOtpEventKeys.contains(_incomingOtpEventKey(match)),
          )
          .toList(growable: false);
      final realtimeSelection = _selectRealtimeOtpMatchesToSync(
        matches,
        newOtpMatches,
        syncNewOtpMatches: syncNewOtpMatches,
        incomingMessagesForSync: incomingMessagesForSync,
      );
      final realtimeOtpMatchesToSync = realtimeSelection.matchesToSync;

      AppLogger.info(
        'OtpReaderPage',
        'Completed OTP filtering.',
        data: <String, Object?>{
          'messagesRead': messages.length,
          'totalMatches': matches.length,
          'newMatches': newOtpMatches.length,
          'realtimeMatchesToSync': realtimeOtpMatchesToSync.length,
          'incomingMessagesForSync': incomingMessagesForSync.length,
          'senderFilters': widget.appConfig.senderFilters,
          'sampleMatches': matches
              .take(5)
              .map((match) => '${match.message.sender}:${match.otpCode}')
              .toList(growable: false),
          if (matches.isEmpty && messages.isNotEmpty)
            'sampleSenders': messages
                .take(5)
                .map((message) => message.sender)
                .toList(growable: false),
        },
      );

      setState(() {
        _totalMessagesRead = messages.length;
        _otpMatches = matches;
      });

      final apiSyncResult = await _sendOtpMatchesToApi(realtimeOtpMatchesToSync);
      _recordForegroundHandledIncomingOtpEventKeys(realtimeSelection.incomingOtpEventKeys);
      _recordOtpMatchesAsSeen(newOtpMatches);
      if (!mounted) {
        return;
      }

      if (apiSyncResult.successfulMatches.isNotEmpty) {
        for (final successfulMatch in apiSyncResult.successfulMatches) {
          await _showApiSuccessNotification(successfulMatch);
          if (!mounted) {
            return;
          }
        }
      }

      if (apiSyncResult.errorMessage != null) {
        AppLogger.warn(
          'OtpReaderPage',
          'OTP sync completed with an API error message.',
          data: <String, Object?>{'errorMessage': apiSyncResult.errorMessage},
        );
        setState(() {
          _errorMessage = apiSyncResult.errorMessage;
        });
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        'OtpReaderPage',
        'OTP inbox read failed.',
        error: error,
        stackTrace: stackTrace,
        data: <String, Object?>{'syncNewOtpMatches': syncNewOtpMatches},
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        AppLogger.info(
          'OtpReaderPage',
          'Finished OTP inbox read.',
          data: <String, Object?>{
            'pendingIncomingRefresh': _pendingIncomingRefresh,
            'queuedIncomingMessages': _queuedIncomingMessages.length,
            'matchCount': _otpMatches.length,
            'errorMessage': _errorMessage,
          },
        );

        if (_pendingIncomingRefresh) {
          _pendingIncomingRefresh = false;
          AppLogger.info(
            'OtpReaderPage',
            'Running queued incoming-message refresh after the current read finished.',
          );
          unawaited(_refreshForIncomingMessages());
        }
      }
    }
  }

  Future<void> _handleRefresh() async {
    if (!widget.smsReaderService.supportsSmsReading) {
      AppLogger.warn(
        'OtpReaderPage',
        'User refresh was ignored because SMS reading is unsupported.',
      );
      return;
    }

    AppLogger.info('OtpReaderPage', 'User triggered a manual refresh.');

    if (!_hasPermission) {
      final shouldRequestPermission = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Allow SMS access?'),
          content: const Text(
            'OTP Message Reader needs SMS permission to scan your inbox for OTP messages.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );

      AppLogger.info(
        'OtpReaderPage',
        'Permission dialog completed during manual refresh.',
        data: <String, Object?>{'shouldRequestPermission': shouldRequestPermission},
      );

      if (shouldRequestPermission != true) {
        return;
      }

      await _requestPermission();
      if (!_hasPermission) {
        return;
      }
    }

    await _readOtpMessages();
  }

  Future<void> _openApiHistoryPage() async {
    AppLogger.info('OtpReaderPage', 'Opening API history page.');
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ApiHistoryPage(smsReaderService: widget.smsReaderService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSupported = widget.smsReaderService.supportsSmsReading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('OTP Message Reader'),
        actions: [
          IconButton(
            key: const ValueKey('open-api-history-button'),
            onPressed: _openApiHistoryPage,
            tooltip: 'API History',
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: AppColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (!_hasPermission) ...[
              ReaderIntroCard(
                isSupported: isSupported,
                isLoading: _isLoading,
                helperText: _helperText,
                onRequestPermission: _requestPermission,
              ),
              const SizedBox(height: 16),
            ],
            ReaderStatusCard(
              totalMessagesRead: _totalMessagesRead,
              otpMatchesCount: _otpMatches.length,
              isLoading: _isLoading,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              PanelCard(
                color: const Color(0xFFFFF4F4),
                borderColor: const Color(0xFFFFD7D7),
                padding: const EdgeInsets.all(16),
                child: Text(
                  _errorMessage!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (_otpMatches.isEmpty)
              PanelCard(
                child: Text(
                  _emptyStateText,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              )
            else
              ..._otpMatches.map(
                (match) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OtpMessageTile(
                    match: match,
                    onTapBody: () => showMessageBodySheet(context, match),
                    onSwipeToSend: () => _sendOtpMatchManually(match),
                    isSwipeActionInProgress: _manualSendInProgressMessageIds
                        .contains(match.message.id),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OtpApiSyncResult {
  const _OtpApiSyncResult({
    this.successfulMatches = const <OtpMatch>[],
    this.errorMessage,
  });

  final List<OtpMatch> successfulMatches;
  final String? errorMessage;
}

class _RealtimeOtpSelection {
  const _RealtimeOtpSelection({
    this.matchesToSync = const <OtpMatch>[],
    this.incomingOtpEventKeys = const <String>[],
  });

  final List<OtpMatch> matchesToSync;
  final List<String> incomingOtpEventKeys;
}