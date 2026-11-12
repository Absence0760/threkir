import 'package:flutter/material.dart';

/// One fact about a plan — its goal, dates or length — as a small glyph and a
/// line of secondary text. The plans list, the library card and the library
/// preview all draw their facts with this, so the same fact cannot read in
/// three styles across three screens. The text is [Flexible], so a long
/// value wraps inside a [Wrap] instead of overflowing at large text sizes.
class PlanMetaItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const PlanMetaItem({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.outline),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
