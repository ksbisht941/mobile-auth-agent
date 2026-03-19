import 'package:flutter/material.dart';

import '../models/otp_match.dart';
import '../theme/app_theme.dart';

class OtpMessageContent extends StatelessWidget {
  const OtpMessageContent({
    super.key,
    required this.match,
    this.maxBodyLines = 2,
    this.onTapBody,
    this.bodyKey,
    this.receivedKey,
  });

  final OtpMatch match;
  final int? maxBodyLines;
  final VoidCallback? onTapBody;
  final Key? bodyKey;
  final Key? receivedKey;

  String _formatReceivedAt(BuildContext context) {
    final receivedAt = match.message.receivedAt.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final dateLabel = localizations.formatMediumDate(receivedAt);
    final timeLabel = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(receivedAt),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

    return 'Received: $dateLabel, $timeLabel';
  }

  @override
  Widget build(BuildContext context) {
    final bodyText = Text(
      key: bodyKey,
      match.message.body,
      maxLines: maxBodyLines,
      overflow: maxBodyLines == null ? null : TextOverflow.ellipsis,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          match.otpCode,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          match.message.sender,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (onTapBody == null)
          bodyText
        else
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTapBody,
            child: bodyText,
          ),
        const SizedBox(height: 8),
        Text(
          key: receivedKey,
          _formatReceivedAt(context),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.mutedText,
          ),
        ),
      ],
    );
  }
}