import 'dart:async';

import 'package:flutter/material.dart';

import '../models/otp_match.dart';
import '../theme/app_theme.dart';
import 'otp_message_content.dart';
import 'panel_card.dart';

class OtpMessageTile extends StatefulWidget {
  static const double _swipeToSendThreshold = 0.3;
  static const double _maxSwipeFraction = 0.4;
  static const Duration _snapBackDuration = Duration(milliseconds: 180);

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
  State<OtpMessageTile> createState() => _OtpMessageTileState();
}

class _OtpMessageTileState extends State<OtpMessageTile> {
  double _dragOffset = 0;
  bool _isDragging = false;

  @override
  void didUpdateWidget(covariant OtpMessageTile oldWidget) {
    super.didUpdateWidget(oldWidget);

    if ((widget.onSwipeToSend == null || widget.isSwipeActionInProgress) &&
        (_dragOffset != 0 || _isDragging)) {
      setState(() {
        _dragOffset = 0;
        _isDragging = false;
      });
    }
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    if (_isDragging) {
      return;
    }

    setState(() {
      _isDragging = true;
    });
  }

  void _handleHorizontalDragUpdate(
    DragUpdateDetails details,
    double maxSwipeOffset,
  ) {
    final primaryDelta = details.primaryDelta;
    if (primaryDelta == null) {
      return;
    }

    final nextOffset = (_dragOffset + primaryDelta).clamp(0.0, maxSwipeOffset);
    if (nextOffset == _dragOffset) {
      return;
    }

    setState(() {
      _dragOffset = nextOffset;
    });
  }

  void _handleHorizontalDragEnd(double triggerOffset) {
    final shouldSend = _dragOffset >= triggerOffset;

    setState(() {
      _dragOffset = 0;
      _isDragging = false;
    });

    if (shouldSend) {
      unawaited(widget.onSwipeToSend?.call());
    }
  }

  void _handleHorizontalDragCancel() {
    if (_dragOffset == 0 && !_isDragging) {
      return;
    }

    setState(() {
      _dragOffset = 0;
      _isDragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final child = SizedBox(
      width: double.infinity,
      child: PanelCard(
        padding: const EdgeInsets.all(16),
        color: AppColors.background,
        borderColor: AppColors.panelBorder,
        child: OtpMessageContent(
          match: widget.match,
          onTapBody: widget.onTapBody,
          bodyKey: ValueKey('message-body-${widget.match.message.id}'),
          receivedKey: ValueKey('message-received-${widget.match.message.id}'),
        ),
      ),
    );

    final onSwipeToSend = widget.onSwipeToSend;
    if (onSwipeToSend == null) {
      return child;
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final tileWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final maxSwipeOffset = tileWidth * OtpMessageTile._maxSwipeFraction;
        final triggerOffset = tileWidth * OtpMessageTile._swipeToSendThreshold;
        final swipeEnabled = !widget.isSwipeActionInProgress;

        return Stack(
          key: ValueKey('otp-message-tile-${widget.match.message.id}'),
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.send_rounded, color: AppColors.background),
                    const SizedBox(width: 8),
                    Text(
                      widget.isSwipeActionInProgress
                          ? 'Sending...'
                          : 'Send to API',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.background,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: swipeEnabled
                  ? _handleHorizontalDragStart
                  : null,
              onHorizontalDragUpdate: swipeEnabled
                  ? (details) =>
                        _handleHorizontalDragUpdate(details, maxSwipeOffset)
                  : null,
              onHorizontalDragEnd: swipeEnabled
                  ? (_) => _handleHorizontalDragEnd(triggerOffset)
                  : null,
              onHorizontalDragCancel: swipeEnabled
                  ? _handleHorizontalDragCancel
                  : null,
              child: AnimatedContainer(
                key: ValueKey(
                  'otp-message-swipe-child-${widget.match.message.id}',
                ),
                duration: _isDragging
                    ? Duration.zero
                    : OtpMessageTile._snapBackDuration,
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(_dragOffset, 0, 0),
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}
