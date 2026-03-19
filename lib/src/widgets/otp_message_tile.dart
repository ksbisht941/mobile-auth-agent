import 'package:flutter/material.dart';

import '../models/otp_match.dart';
import '../theme/app_theme.dart';
import 'otp_message_content.dart';
import 'panel_card.dart';

class OtpMessageTile extends StatelessWidget {
  const OtpMessageTile({
    super.key,
    required this.match,
    required this.onTapBody,
    this.onSwipeToSend,
    this.isSwipeActionInProgress = false,
  });

  final OtpMatch match;
  final VoidCallback onTapBody;
  final Future<void> Function()? onSwipeToSend;
  final bool isSwipeActionInProgress;

  @override
  Widget build(BuildContext context) {
    final child = PanelCard(
      padding: const EdgeInsets.all(16),
      color: AppColors.background,
      borderColor: AppColors.panelBorder,
      child: OtpMessageContent(
        match: match,
        onTapBody: onTapBody,
        bodyKey: ValueKey('message-body-${match.message.id}'),
        receivedKey: ValueKey('message-received-${match.message.id}'),
      ),
    );

    final onSwipeToSend = this.onSwipeToSend;
    if (onSwipeToSend == null) {
      return child;
    }

    return Dismissible(
      key: ValueKey('otp-message-tile-${match.message.id}'),
      direction: isSwipeActionInProgress
          ? DismissDirection.none
          : DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await onSwipeToSend();
        return false;
      },
      background: const SizedBox.shrink(),
      secondaryBackground: Container(
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.send_rounded, color: AppColors.background),
            const SizedBox(width: 8),
            Text(
              isSwipeActionInProgress ? 'Sending...' : 'Send to API',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.background,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      child: child,
    );
  }
}