import 'package:flutter/material.dart';

/// One control in the Run tab's idle setup row (route, live link, guided run,
/// race strategy, plan). Every item in the row is this one widget, so the
/// only visual difference between two items is whether something is set:
/// an outlined pill (the chip theme's outline) when it isn't, a tonal
/// `secondaryContainer` fill when it is, so a configured item does not read
/// as the selected activity type in the coral `ChoiceChip`s above it.
///
/// [onClear] adds an x that removes the setting. It is an [IconButton] rather
/// than an `InputChip` delete icon because the chip's delete hit area is
/// narrower than 48 dp; the button carries the full 48 x 48 target and its
/// own screen-reader label from [clearTooltip].
class IdleSetupChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSet;
  final VoidCallback onPressed;
  final VoidCallback? onClear;
  final String? clearTooltip;

  const IdleSetupChip({
    super.key,
    required this.icon,
    required this.label,
    required this.isSet,
    required this.onPressed,
    this.onClear,
    this.clearTooltip,
  }) : assert(onClear == null || clearTooltip != null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = isSet ? scheme.onSecondaryContainer : scheme.onSurface;
    final iconColor = isSet ? fg : scheme.primary;
    final outline = theme.chipTheme.side ?? BorderSide(color: theme.dividerColor);
    final clearable = onClear != null;
    return Material(
      color: isSet ? scheme.secondaryContainer : Colors.transparent,
      shape: StadiumBorder(
        side: isSet ? BorderSide.none : outline,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Semantics(
              button: true,
              selected: isSet,
              child: InkWell(
                onTap: onPressed,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                      minHeight: kMinInteractiveDimension),
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                        start: 14, end: clearable ? 2 : 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 18, color: iconColor),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge
                                ?.copyWith(color: fg),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (clearable)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: fg,
              tooltip: clearTooltip,
              onPressed: onClear,
            ),
        ],
      ),
    );
  }
}
