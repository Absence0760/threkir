import 'package:flutter/material.dart';

/// The eyebrow that names a group of rows in a list — a settings section, a
/// bucket of routes in a picker.
///
/// One typography for every such group: `labelSmall`, the §482 micro-label
/// floor, uppercased, weight 700, on `onSurfaceVariant` rather than
/// `colorScheme.outline` for the same reason [ChartCardHeader] gives — at
/// 11 sp, `outline`'s 4.058:1 on the light card is under WCAG 1.4.3's 4.5:1.
///
/// [SectionHeader.title] is the other form a section heading takes: the
/// `titleMedium` heading of a block within a scrolling body (a card's title,
/// a detail page's section), not uppercased and announced as a heading. Both
/// forms live here so no screen hand-builds either one.
///
/// Distinct from [ChartCardHeader], which titles a data-visualisation card and
/// carries a right-aligned note slot.
///
/// Padding is the caller's: a list group's inset belongs to the list
/// ([SettingsList] owns it for every settings page).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.label,
    this.icon,
    this.iconColor,
    this.trailing,
  }) : _title = false;

  const SectionHeader.title({
    super.key,
    required this.label,
    this.icon,
    this.iconColor,
    this.trailing,
  }) : _title = true;

  final bool _title;

  final String label;

  /// A leading glyph identifying the group. [iconColor] carries the group's
  /// own semantic colour when it has one.
  final IconData? icon;
  final Color? iconColor;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon,
              size: _title ? 20 : 16,
              color: iconColor ?? theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: _title
              ? Semantics(
                  header: true,
                  child: Text(
                    label,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                )
              : Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
