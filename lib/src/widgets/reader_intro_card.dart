import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'panel_card.dart';

class ReaderIntroCard extends StatelessWidget {
  const ReaderIntroCard({
    super.key,
    required this.isSupported,
    required this.isLoading,
    required this.helperText,
    required this.onRequestPermission,
  });

  final bool isSupported;
  final bool isLoading;
  final String helperText;
  final VoidCallback onRequestPermission;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Read SMS messages from Android and keep only OTP-like messages.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            helperText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.mutedText,
            ),
          ),
          const SizedBox(height: 16),
          if (!isSupported)
            Text(
              'SMS reading is available on Android only.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton(
                  onPressed: isLoading ? null : onRequestPermission,
                  child: Text('Grant SMS permission'),
                ),
                // FilledButton.icon(
                //   onPressed: !hasPermission || isLoading
                //       ? null
                //       : _readOtpMessages,
                //   icon: const Icon(Icons.sms_outlined),
                //   label: const Text('Read OTP messages'),
                // ),
              ],
            ),
        ],
      ),
    );
  }
}