import 'package:flutter/material.dart';

import '../models/otp_match.dart';
import '../theme/app_theme.dart';
import 'otp_message_content.dart';

Future<void> showMessageBodySheet(BuildContext context, OtpMatch match) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // PanelCard(
              // child: 
              OtpMessageContent(
                match: match,
                maxBodyLines: null,
                bodyKey: ValueKey('sheet-message-body-${match.message.id}'),
                receivedKey: ValueKey(
                  'sheet-message-received-${match.message.id}',
                ),
              ),
            // ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
