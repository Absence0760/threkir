import 'package:flutter/material.dart';

/// One lift's next target on a from-routine gym session: the exercise, the
/// change, and why. Neutral / positive treatment, never the red / amber
/// adherence colours.
///
/// The three parts are one paragraph that wraps inside the chip. As three
/// unflexed `Text`s in a `Row` the chip never wrapped, so "Barbell back
/// squat" with "Establish baseline — set a starting weight" ran off a
/// 320 dp card in English at 1.0x (issue #1374 TO-4).
class NextTargetChip extends StatelessWidget {
  const NextTargetChip({
    super.key,
    required this.exercise,
    required this.delta,
    required this.reason,
    required this.deload,
  });

  final String exercise;

  /// Already formatted ("+2.5 kg", "+1 rep"); null when there is no change
  /// to show.
  final String? delta;
  final String reason;
  final bool deload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = theme.colorScheme.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            deload ? Icons.trending_down : Icons.trending_up,
            size: MediaQuery.textScalerOf(context).scale(14),
            color: on,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text.rich(
              TextSpan(
                style: theme.textTheme.labelSmall?.copyWith(color: on),
                children: [
                  TextSpan(
                    text: exercise,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (delta != null)
                    TextSpan(
                      text: '  $delta',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  TextSpan(text: '  $reason'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
