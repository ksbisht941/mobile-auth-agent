import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../models/api_call_history_entry.dart';
import '../services/sms_reader_service.dart';
import '../theme/app_theme.dart';
import '../widgets/panel_card.dart';
import '../widgets/section_header.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.initialConfig,
    required this.smsReaderService,
  });

  final AppConfig initialConfig;
  final SmsReaderService smsReaderService;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static final RegExp _dtmfDigitPattern = RegExp(r'^[0-9*#A-D]$');

  late final TextEditingController _senderFiltersController;
  late final TextEditingController _autoAnswerNumbersController;
  late final TextEditingController _autoHangUpDelaySecondsController;
  late final List<_PostAnswerDtmfStepEditor> _postAnswerDtmfStepEditors;
  late bool _autoHandleEnabled;
  bool _isLoadingHistory = true;
  String? _historyErrorMessage;
  List<ApiCallHistoryEntry> _historyEntries = const <ApiCallHistoryEntry>[];

  @override
  void initState() {
    super.initState();
    _autoHandleEnabled = widget.initialConfig.autoHandleEnabled;
    _senderFiltersController = TextEditingController(
      text: widget.initialConfig.senderFilters.join('\n'),
    );
    _autoAnswerNumbersController = TextEditingController(
      text: widget.initialConfig.autoAnswerNumbers.join('\n'),
    );
    _autoHangUpDelaySecondsController = TextEditingController(
      text: widget.initialConfig.autoHangUpDelaySeconds.toString(),
    );
    _postAnswerDtmfStepEditors = widget.initialConfig.postAnswerDtmfSteps
        .map(_PostAnswerDtmfStepEditor.fromStep)
        .toList(growable: true);
    _loadHistory();
  }

  @override
  void dispose() {
    _senderFiltersController.dispose();
    _autoAnswerNumbersController.dispose();
    _autoHangUpDelaySecondsController.dispose();
    for (final editor in _postAnswerDtmfStepEditors) {
      editor.dispose();
    }
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoadingHistory = true;
      _historyErrorMessage = null;
    });

    try {
      final historyEntries = await widget.smsReaderService.getApiCallHistory();
      if (!mounted) {
        return;
      }

      setState(() {
        _historyEntries = historyEntries;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _historyErrorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
        });
      }
    }
  }

  void _saveSettings() {
    Navigator.of(context).pop(
      widget.initialConfig.copyWith(
        senderFilters: _parseSenderFilters(_senderFiltersController.text),
        autoHandleEnabled: _autoHandleEnabled,
        autoAnswerNumbers: _parseAutoAnswerNumbers(
          _autoAnswerNumbersController.text,
        ),
        autoHangUpDelaySeconds: _parseAutoHangUpDelaySeconds(
          _autoHangUpDelaySecondsController.text,
        ),
        postAnswerDtmfSteps: _parsePostAnswerDtmfSteps(),
      ),
    );
  }

  List<PostAnswerDtmfStep> _parsePostAnswerDtmfSteps() {
    return _postAnswerDtmfStepEditors
        .map((editor) {
          final digit = _parseDtmfDigit(
            editor.digitController.text,
            fallbackValue: editor.initialDigit,
          );
          if (digit.isEmpty) {
            return null;
          }

          return PostAnswerDtmfStep(
            digit: digit,
            delaySeconds: _parseNonNegativeInt(
              editor.delaySecondsController.text,
              fallbackValue: editor.initialDelaySeconds,
            ),
          );
        })
        .whereType<PostAnswerDtmfStep>()
        .toList(growable: false);
  }

  void _addPostAnswerDtmfStep() {
    setState(() {
      _postAnswerDtmfStepEditors.add(_PostAnswerDtmfStepEditor.empty());
    });
  }

  void _removePostAnswerDtmfStep(int index) {
    setState(() {
      final editor = _postAnswerDtmfStepEditors.removeAt(index);
      editor.dispose();
    });
  }

  List<String> _splitEntries(String rawValue) => rawValue
      .split(RegExp(r'[,\n]'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);

  List<String> _parseSenderFilters(String rawValue) {
    final seenValues = <String>{};
    return _splitEntries(rawValue)
        .where((value) => seenValues.add(value.toLowerCase()))
        .toList(growable: false);
  }

  List<String> _parseAutoAnswerNumbers(String rawValue) {
    final seenValues = <String>{};
    return _splitEntries(rawValue)
        .where((value) {
          final normalizedDigits = value.replaceAll(RegExp(r'[^0-9]'), '');
          final dedupeKey = normalizedDigits.isNotEmpty
              ? normalizedDigits
              : value.toLowerCase();
          return seenValues.add(dedupeKey);
        })
        .toList(growable: false);
  }

  int _parseAutoHangUpDelaySeconds(String rawValue) {
    return _parseNonNegativeInt(
      rawValue,
      fallbackValue: widget.initialConfig.autoHangUpDelaySeconds,
    );
  }

  int _parseNonNegativeInt(String rawValue, {required int fallbackValue}) {
    final parsedValue = int.tryParse(rawValue.trim());
    if (parsedValue == null) {
      return fallbackValue;
    }
    if (parsedValue < 0) {
      return 0;
    }
    return parsedValue;
  }

  String _parseDtmfDigit(String rawValue, {required String fallbackValue}) {
    final normalizedValue = rawValue.trim().toUpperCase();
    if (normalizedValue.isEmpty) {
      return '';
    }

    final candidate = normalizedValue.substring(0, 1);
    return _dtmfDigitPattern.hasMatch(candidate) ? candidate : fallbackValue;
  }

  String _formatDateTime(BuildContext context, DateTime value) {
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatMediumDate(value)}, '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value))}';
  }

  Widget _buildHistoryEntry(BuildContext context, ApiCallHistoryEntry entry) {
    final theme = Theme.of(context);
    final statusColor = entry.isSuccess
        ? const Color(0xFF1D7D46)
        : const Color(0xFFB42318);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'OTP ${entry.otpCode} • ${entry.sender}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                entry.isSuccess ? 'Success' : 'Failed',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'SMS received: ${_formatDateTime(context, entry.smsReceivedAt)}',
          ),
          const SizedBox(height: 4),
          Text('API called: ${_formatDateTime(context, entry.apiCalledAt)}'),
          if (entry.statusCode != null) ...[
            const SizedBox(height: 4),
            Text('Status code: ${entry.statusCode}'),
          ],
          if (entry.errorMessage != null && entry.errorMessage!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Error: ${entry.errorMessage}'),
          ],
        ],
      ),
    );
  }

  Widget _buildHistorySection(BuildContext context) {
    final theme = Theme.of(context);

    return PanelCard(
      key: const ValueKey('settings-api-history-section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: const SectionHeader(
                  icon: Icons.history,
                  title: 'API history',
                ),
              ),
              IconButton(
                key: const ValueKey('settings-refresh-history-button'),
                onPressed: _isLoadingHistory ? null : _loadHistory,
                tooltip: 'Refresh history',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Showing the latest ${_historyEntries.length} saved API calls.',
            style: theme.textTheme.bodyMedium,
          ),
          if (_isLoadingHistory) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ] else if (_historyErrorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4F4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFD7D7)),
              ),
              child: Text(_historyErrorMessage!),
            ),
          ] else if (_historyEntries.isEmpty) ...[
            const SizedBox(height: 16),
            Text('No API history saved yet.', style: theme.textTheme.bodyLarge),
          ] else
            ..._historyEntries.map(
              (entry) => _buildHistoryEntry(context, entry),
            ),
        ],
      ),
    );
  }

  Widget _buildPostAnswerDtmfStepEditor(BuildContext context, int index) {
    final editor = _postAnswerDtmfStepEditors[index];

    return Container(
      key: ValueKey('settings-post-answer-dtmf-step-$index'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Step ${index + 1}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                key: ValueKey(
                  'settings-post-answer-dtmf-remove-step-button-$index',
                ),
                tooltip: 'Remove step ${index + 1}',
                onPressed: () => _removePostAnswerDtmfStep(index),
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey('settings-post-answer-dtmf-digit-field-$index'),
                  controller: editor.digitController,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                  inputFormatters: <TextInputFormatter>[
                    LengthLimitingTextInputFormatter(1),
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9*#A-Da-d]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Key',
                    hintText: '1',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  key: ValueKey(
                    'settings-post-answer-dtmf-delay-seconds-field-$index',
                  ),
                  controller: editor.delaySecondsController,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Delay (s)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(
            key: const ValueKey('save-settings-button'),
            onPressed: _saveSettings,
            child: const Text('Save'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        color: AppColors.primary,
        child: ListView(
          key: const ValueKey('settings-page-list-view'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile.adaptive(
                  key: const ValueKey('settings-auto-handle-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Auto handle OTP messages and calls',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  value: _autoHandleEnabled,
                  onChanged: (value) {
                    setState(() {
                      _autoHandleEnabled = value;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                    icon: Icons.filter_alt_outlined,
                    title: 'Sender filters',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('settings-sender-filters-field'),
                    controller: _senderFiltersController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText: 'SMS-XXXXX',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                    icon: Icons.call_outlined,
                    title: 'Auto-answer numbers',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('settings-auto-answer-numbers-field'),
                    controller: _autoAnswerNumbersController,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText: '+91 XXXXXXXXXX',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('settings-auto-hangup-seconds-field'),
                    controller: _autoHangUpDelaySecondsController,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Auto hang-up delay (seconds)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            PanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                    icon: Icons.dialpad_outlined,
                    title: 'After pickup keypad actions',
                  ),
                  const SizedBox(height: 12),
                  ...List<Widget>.generate(
                    _postAnswerDtmfStepEditors.length,
                    (index) => _buildPostAnswerDtmfStepEditor(context, index),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const ValueKey(
                        'settings-post-answer-dtmf-add-step-button',
                      ),
                      onPressed: _addPostAnswerDtmfStep,
                      icon: const Icon(Icons.add),
                      label: const Text('Add step'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildHistorySection(context),
          ],
        ),
      ),
    );
  }
}

class _PostAnswerDtmfStepEditor {
  _PostAnswerDtmfStepEditor({
    required this.initialDigit,
    required this.initialDelaySeconds,
  }) : digitController = TextEditingController(text: initialDigit),
       delaySecondsController = TextEditingController(
         text: initialDelaySeconds.toString(),
       );

  factory _PostAnswerDtmfStepEditor.fromStep(PostAnswerDtmfStep step) {
    return _PostAnswerDtmfStepEditor(
      initialDigit: step.digit,
      initialDelaySeconds: step.delaySeconds,
    );
  }

  factory _PostAnswerDtmfStepEditor.empty() {
    return _PostAnswerDtmfStepEditor(initialDigit: '', initialDelaySeconds: 0);
  }

  final String initialDigit;
  final int initialDelaySeconds;
  final TextEditingController digitController;
  final TextEditingController delaySecondsController;

  void dispose() {
    digitController.dispose();
    delaySecondsController.dispose();
  }
}
