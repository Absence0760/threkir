import 'package:flutter/material.dart';

import '../theme/spacing.dart';

/// The one line at the head of a filtered list saying what it shows ("This
/// week · 5 runs · 42 km", "18 of 20 routes", "1 of 3 plans"), with an
/// optional action such as Clear filters at its end. Runs, Routes and Plans
/// each drew their own in a different style; this is the one style, and the
/// count of what is shown lives here, never on the quick chips (issue #1374).
///
/// The text wraps rather than ellipsizing, so at 2x text on a narrow phone
/// nothing is cut.
class ListSummary extends StatelessWidget {
  const ListSummary({super.key, required this.text, this.action});

  final String text;

  /// Usually a `TextButton`.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
