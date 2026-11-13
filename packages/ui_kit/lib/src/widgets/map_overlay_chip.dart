import 'package:flutter/material.dart';

import '../theme/spacing.dart';

/// A short status floating over a map or the recorder: "Loading GPS…", "GPS
/// unavailable", "1.2 km to the start line", "Phase 2 of 4 · settle".
///
/// Run detail and the recorder each drew these as a bare `Card` around a
/// `Padding`: the card's list margin and corner on something that is not a
/// list item, and a `Row` that ran off the map in a long translation at large
/// text (issue #1374). This is one raised stadium on the surface colour whose
/// label wraps to a second line rather than overflowing; the caller bounds it
/// (a `Positioned` with both edges, or a `Center` in a column), never a bare
/// `Positioned(right:)`, which would give it no width to wrap in.
class MapOverlayChip extends StatelessWidget {
  const MapOverlayChip({super.key, required this.label, this.leading});

  /// Already localized.
  final String label;

  /// A small glyph or a spinner, about 14 dp.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final leading = this.leading;
    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.smPlus,
          vertical: AppSpace.xs + 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              leading,
              const SizedBox(width: AppSpace.sm),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
