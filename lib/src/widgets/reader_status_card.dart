import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'panel_card.dart';
import 'section_header.dart';

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
    final theme = Theme.of(context);

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            icon: Icons.mark_email_read_outlined,
            title: 'OTP inbox',
          ),
          const SizedBox(height: 16),
          Text(
            'Messages scanned: $totalMessagesRead',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'OTP matches found: $otpMatchesCount',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.mutedText,
            ),
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
