import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart' show AppSemanticColors;

/// One toolbar action, renderable either as a visible [IconButton] or as a
/// row in the overflow menu: the same action, two presentations, so the
/// budget can move it without the caller restating it.
class AppBarAction {
  const AppBarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconColor,
    this.destructive = false,
    this.key,
  });

  /// Drawn in both presentations. A [Widget] rather than an `IconData` so a
  /// busy action can swap in its spinner without a second code path.
  final Widget icon;

  /// Tooltip while visible, menu row title once it overflows. There is no
  /// separate short form: an action whose name only works as a tooltip has
  /// no name a user can act on.
  final String label;

  /// Null disables the action in both presentations.
  final VoidCallback? onPressed;

  final Color? iconColor;

  /// Destroys data or a relationship the user cannot restore, or reports
  /// someone (decisions § 498). Sits last, behind a divider, in the danger
  /// colour, and is never promoted into a visible slot, where a mis-tap has
  /// no confirmation step before the dialog.
  final bool destructive;

  /// Put on the visible button or on the menu row, whichever renders, so a
  /// test finds the action in either place.
  final Key? key;
}

/// An `AppBar.actions` list that keeps the title readable.
///
/// A Material toolbar spends 72 dp before the title (a 56 dp leading slot plus
/// the 16 dp title gap), 48 on each action and 16 after the last, so the title
/// gets `width - 88 - 48n`. Six concurrent actions on a 360 dp phone measure
/// 0 dp of title; three measure 128.
///
/// [pinned] widgets always render (a share `PopupMenuButton` cannot fold into
/// another menu without nesting one) and count against [maxVisible]; the
/// first of [actions] fill whatever budget is left, in the order given, and
/// the rest go to a single overflow menu. Order [actions] by how often the
/// screen's user reaches for them: the head of the list is what earns a
/// toolbar slot.
///
/// While [busyLabel] is set the overflow button is a spinner announced with
/// it (a delete in flight), so nothing in the menu can be started twice.
class ToolbarActions extends StatelessWidget {
  const ToolbarActions({
    super.key,
    required this.actions,
    this.pinned = const [],
    this.maxVisible = 3,
    this.moreTooltip,
    this.busyLabel,
  });

  final List<AppBarAction> actions;
  final List<Widget> pinned;

  /// Total toolbar slots, including [pinned] and the overflow button itself.
  /// Three is what fits beside a title on a 360 dp phone.
  final int maxVisible;

  /// The overflow button's tooltip. Defaults to Material's localized "More".
  final String? moreTooltip;

  final String? busyLabel;

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    final danger = semantic?.danger ?? Theme.of(context).colorScheme.error;
    // The overflow button costs a slot of its own, unless every action fits
    // without one.
    final free = maxVisible - pinned.length;
    final slots =
        actions.length <= free ? actions.length : math.max(0, free - 1);
    final visible = <AppBarAction>[];
    final overflow = <AppBarAction>[];
    for (final action in actions) {
      if (!action.destructive && visible.length < slots) {
        visible.add(action);
      } else {
        overflow.add(action);
      }
    }
    final busyLabel = this.busyLabel;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...pinned,
        for (final action in visible)
          IconButton(
            key: action.key,
            icon: IconTheme.merge(
              data: IconThemeData(color: action.iconColor),
              child: action.icon,
            ),
            tooltip: action.label,
            onPressed: action.onPressed,
          ),
        if (busyLabel != null)
          SizedBox.square(
            dimension: kMinInteractiveDimension,
            child: Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  semanticsLabel: busyLabel,
                ),
              ),
            ),
          )
        else if (overflow.isNotEmpty)
          PopupMenuButton<int>(
            tooltip: moreTooltip ??
                MaterialLocalizations.of(context).moreButtonTooltip,
            onSelected: (i) => overflow[i].onPressed?.call(),
            itemBuilder: (_) => [
              for (var i = 0; i < overflow.length; i++) ...[
                if (overflow[i].destructive && i > 0) const PopupMenuDivider(),
                PopupMenuItem<int>(
                  key: overflow[i].key,
                  value: i,
                  enabled: overflow[i].onPressed != null,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: IconTheme.merge(
                      data: IconThemeData(
                        color: overflow[i].destructive
                            ? danger
                            : overflow[i].iconColor,
                      ),
                      child: overflow[i].icon,
                    ),
                    title: Text(
                      overflow[i].label,
                      style: overflow[i].destructive
                          ? TextStyle(color: danger)
                          : null,
                    ),
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}
