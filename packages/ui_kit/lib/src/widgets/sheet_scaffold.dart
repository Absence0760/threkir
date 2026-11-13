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
    required Widget this.body,
    this.actions,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
    this.scrollBody = true,
  }) : floating = false,
       pinned = null,
       slivers = null,
       initialSize = 0;

  /// A share preview's sheet: the same title, body and actions on a rounded
  /// surface card that floats [padding] clear of the screen edges, for a
  /// sheet opened with `backgroundColor: Colors.transparent` and no drag
  /// handle, so the card reads as the thing being shared.
  const SheetScaffold.floating({
    super.key,
    this.title,
    required Widget this.body,
    this.actions,
    this.padding = const EdgeInsets.all(16),
    this.scrollBody = true,
  }) : floating = true,
       pinned = null,
       slivers = null,
       initialSize = 0;

  /// A tall sheet for a long list someone searches or scrolls through (a
  /// route library, a contact list). It opens at [initialSize] of the screen
  /// and drags up to the full height; [title] and [pinned] (the search field)
  /// stay put while [slivers] scroll under them. It takes the whole screen
  /// when anything in [pinned] gains focus, so the keyboard never leaves a
  /// sliver of list, and a drag on the list grows the sheet before it
  /// scrolls, so a long library is never read through a 70% window. The
  /// sheet sits above the keyboard rather than under it, and the list ends
  /// clear of the nav bar.
  ///
  /// Open it with `showModalBottomSheet(isScrollControlled: true,
  /// useSafeArea: true)`: without `isScrollControlled` the route caps the
  /// sheet at 9/16 of the screen, which it then cannot grow past.
  const SheetScaffold.expanding({
    super.key,
    this.title,
    this.pinned,
    required List<Widget> this.slivers,
    this.initialSize = 0.7,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  }) : body = null,
       actions = null,
       scrollBody = false,
       floating = false;

  /// Shown in `titleLarge` above the body.
  final Widget? title;

  /// Null only on [SheetScaffold.expanding], which takes [slivers].
  final Widget? body;

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

  /// [SheetScaffold.expanding]'s header below the title, kept on screen while
  /// the list scrolls: a search field, a filter row.
  final Widget? pinned;

  /// [SheetScaffold.expanding]'s list. Non-null exactly there.
  final List<Widget>? slivers;

  /// The fraction of the screen [SheetScaffold.expanding] opens at.
  final double initialSize;

  @override
  Widget build(BuildContext context) {
    if (slivers case final slivers?) {
      return _ExpandingSheet(
        title: title,
        pinned: pinned,
        slivers: slivers,
        initialSize: initialSize,
        padding: padding,
      );
    }
    final theme = Theme.of(context);
    final body = scrollBody
        ? SingleChildScrollView(child: this.body)
        : this.body!;
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

class _ExpandingSheet extends StatefulWidget {
  const _ExpandingSheet({
    required this.title,
    required this.pinned,
    required this.slivers,
    required this.initialSize,
    required this.padding,
  });

  final Widget? title;
  final Widget? pinned;
  final List<Widget> slivers;
  final double initialSize;
  final EdgeInsets padding;

  @override
  State<_ExpandingSheet> createState() => _ExpandingSheetState();
}

class _ExpandingSheetState extends State<_ExpandingSheet> {
  final _sheet = DraggableScrollableController();

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  void _onPinnedFocus(bool focused) {
    if (focused) _expand();
  }

  /// A drag on the list grows the sheet before it scrolls; a scroll that
  /// reaches the list some other way (a screen reader's scroll action, a
  /// focus move to a row below the fold) grows it too.
  bool _onScroll(ScrollUpdateNotification n) {
    if (n.depth == 0 && n.metrics.pixels > 0) _expand();
    return false;
  }

  void _expand() {
    if (!_sheet.isAttached || _sheet.size >= 1) return;
    _sheet.animateTo(
      1,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final navBar = keyboard > 0
        ? 0.0
        : MediaQuery.viewPaddingOf(context).bottom;
    final fill =
        theme.bottomSheetTheme.modalBackgroundColor ??
        theme.bottomSheetTheme.backgroundColor ??
        theme.colorScheme.surfaceContainerLow;
    final pad = widget.padding;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: DraggableScrollableSheet(
        controller: _sheet,
        expand: false,
        initialChildSize: widget.initialSize,
        minChildSize: 0.25,
        maxChildSize: 1,
        snap: true,
        snapSizes: [widget.initialSize],
        builder: (context, scroll) =>
            NotificationListener<ScrollUpdateNotification>(
              onNotification: _onScroll,
              child: CustomScrollView(
                controller: scroll,
                slivers: [
                  PinnedHeaderSliver(
                    child: ColoredBox(
                      color: fill,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          pad.left,
                          pad.top,
                          pad.right,
                          8,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.title case final title?)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: DefaultTextStyle.merge(
                                  style: theme.textTheme.titleLarge,
                                  child: title,
                                ),
                              ),
                            if (widget.pinned case final pinned?)
                              Focus(
                                canRequestFocus: false,
                                skipTraversal: true,
                                onFocusChange: _onPinnedFocus,
                                child: pinned,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.only(
                      left: pad.left,
                      right: pad.right,
                      bottom: pad.bottom + navBar,
                    ),
                    sliver: SliverMainAxisGroup(slivers: widget.slivers),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
