import 'package:flutter/material.dart';

import '../theme/corner_radii.dart';

/// The bottom inset a sheet or a form body has to clear: the soft keyboard
/// while it is up (`viewInsets.bottom`), otherwise the gesture / 3-button
/// nav bar (`viewPadding.bottom`). The two never stack, because the keyboard
/// covers the nav bar, so whichever is non-zero is the one to clear.
double systemBottomInset(BuildContext context) {
  final keyboard = MediaQuery.viewInsetsOf(context).bottom;
  return keyboard > 0 ? keyboard : MediaQuery.viewPaddingOf(context).bottom;
}

/// The one layout for a modal bottom sheet's content: optional title, a body
/// that scrolls when it outgrows the sheet, and an optional action row pinned
/// below it, all lifted clear of the keyboard and the system nav bar.
///
/// `showModalBottomSheet(useSafeArea: true)` keeps a sheet out from under the
/// status bar but deliberately not the bottom bar, so clearing the bottom is
/// the content's job. Sheets that padded for `viewInsets` alone drew their
/// Save row under a 3-button nav bar, where a tap landed on Back or Home
/// (issue #1374 IK-1). The drag handle is `bottomSheetTheme.showDragHandle`,
/// so this draws none.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    this.title,
    required this.body,
    this.actions,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
    this.scrollBody = true,
  }) : floating = false;

  /// A share preview's sheet: the same title, body and actions on a rounded
  /// surface card that floats [padding] clear of the screen edges, for a
  /// sheet opened with `backgroundColor: Colors.transparent` and no drag
  /// handle, so the card reads as the thing being shared.
  const SheetScaffold.floating({
    super.key,
    this.title,
    required this.body,
    this.actions,
    this.padding = const EdgeInsets.all(16),
    this.scrollBody = true,
  }) : floating = true;

  /// Shown in `titleLarge` above the body.
  final Widget? title;

  final Widget body;

  /// The action row, pinned below the body so it stays on screen however
  /// long the body grows. The caller lays it out (an end-aligned
  /// `OverflowBar`, a pair of `Expanded` buttons). Null for a sheet whose body
  /// is its own action (a list of choices, a picker).
  final Widget? actions;

  /// Around the whole sheet; the system inset is added to its bottom.
  final EdgeInsets padding;

  /// False when [body] is already a scrollable (a `ListView`), which then
  /// takes the space left between the title and the actions.
  final bool scrollBody;

  /// Built by [SheetScaffold.floating].
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = scrollBody
        ? SingleChildScrollView(child: this.body)
        : this.body;
    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title case final title?)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DefaultTextStyle.merge(
              style: theme.textTheme.titleLarge,
              child: title,
            ),
          ),
        Flexible(child: body),
        if (actions case final actions?)
          Padding(padding: const EdgeInsets.only(top: 12), child: actions),
      ],
    );
    if (floating) {
      content = Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        padding: const EdgeInsets.all(16),
        child: content,
      );
    }
    return Padding(
      padding: padding.copyWith(
        bottom: padding.bottom + systemBottomInset(context),
      ),
      child: content,
    );
  }
}
