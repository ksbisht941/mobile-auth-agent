import 'package:flutter/material.dart';

import 'panel_card.dart';
import 'section_header.dart';

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
          SectionHeader(
            icon: Icons.sms_outlined,
            title: 'SMS access',
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
