import 'package:flutter/material.dart';

import 'panel_card.dart';

class ReaderStatusCard extends StatelessWidget {
  const ReaderStatusCard({
    super.key,
    required this.totalMessagesRead,
    required this.otpMatchesCount,
    required this.isLoading,
  });

  final int totalMessagesRead;
  final int otpMatchesCount;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Messages scanned: $totalMessagesRead',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'OTP matches found: $otpMatchesCount',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (isLoading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}