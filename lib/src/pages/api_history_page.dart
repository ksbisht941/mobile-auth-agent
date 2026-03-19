import 'package:flutter/material.dart';

import '../models/api_call_history_entry.dart';
import '../services/sms_reader_service.dart';
import '../theme/app_theme.dart';
import '../widgets/panel_card.dart';

class ApiHistoryPage extends StatefulWidget {
  const ApiHistoryPage({super.key, required this.smsReaderService});

  final SmsReaderService smsReaderService;

  @override
  State<ApiHistoryPage> createState() => _ApiHistoryPageState();
}

class _ApiHistoryPageState extends State<ApiHistoryPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<ApiCallHistoryEntry> _historyEntries = const <ApiCallHistoryEntry>[];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
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
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatDateTime(BuildContext context, DateTime value) {
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatMediumDate(value)}, '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value))}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API History')),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        color: AppColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            PanelCard(
              child: Text(
                'Showing the latest ${_historyEntries.length} saved API calls.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            if (_isLoading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              PanelCard(
                color: const Color(0xFFFFF4F4),
                borderColor: const Color(0xFFFFD7D7),
                padding: const EdgeInsets.all(16),
                child: Text(_errorMessage!),
              ),
            ] else if (!_isLoading && _historyEntries.isEmpty) ...[
              const SizedBox(height: 16),
              PanelCard(
                child: Text(
                  'No API history saved yet.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ] else ...[
              const SizedBox(height: 16),
              ..._historyEntries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: PanelCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'OTP ${entry.otpCode} • ${entry.isSuccess ? 'Success' : 'Failed'}',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Sender: ${entry.sender}'),
                        const SizedBox(height: 4),
                        Text('SMS received: ${_formatDateTime(context, entry.smsReceivedAt)}'),
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
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}