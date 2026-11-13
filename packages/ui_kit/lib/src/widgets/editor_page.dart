import 'package:flutter/material.dart';

import '../theme/spacing.dart';
import 'pushed_page.dart';

/// The one primary action an [EditorPage] pins: Save, Create, Add, Join.
///
/// A value, not a button: the page decides where it goes and how it looks,
/// which is what keeps an editor to exactly one primary action.
class EditorSave {
  const EditorSave({
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.key,
  });

  /// The button's text. While [busy] it should name the work in progress
  /// ("Saving…"), since a spinner alone says nothing to a screen reader.
  final String label;

  /// Null draws the button disabled.
  final VoidCallback? onPressed;

  /// Draws a spinner beside [label] and disables the button.
  final bool busy;

  /// The rendered button's key, for a test to find it by.
  final Key? key;
}

/// The one layout for a full-page create / edit form: an app bar with a close
/// button, the title at the top of the fields (the bar repeats it once it has
/// scrolled away), the fields in a body that always scrolls, and the
/// [save] action pinned in a bar under them, above the keyboard and the
/// system navigation bar.
///
/// Issue #1374: editors placed Save by hand at the end of a scroll (off
/// screen under the keyboard), in the app bar and again in the body (two
/// Saves), or in a `bottomNavigationBar` the keyboard covers; a short form
/// that did not scroll overflowed under the keyboard at large text or in
/// landscape (IK-11), and a Cancel / Save row with no wrap clipped Save off
/// the edge at large text (TO-7). Here the body scrolls, the bar sits in the
/// body's column so the scaffold lifts it with the keyboard, and the action
/// row wraps: one full-width Save, or [secondary] and Save on one line that
/// stacks when the two do not fit.
///
/// There is no Cancel: the close button is the way out, and it goes through
/// `Navigator.maybePop`, so a discard guard above the page is asked first.
///
/// Strings come from the caller; ui_kit has no catalogue.
class EditorPage extends StatelessWidget {
  const EditorPage({
    super.key,
    required this.title,
    required this.fields,
    this.save,
    this.secondary,
    this.status,
    this.actions = const [],
    this.placeholder,
    this.padding = const EdgeInsets.fromLTRB(
      AppInsets.gutter,
      AppSpace.md,
      AppInsets.gutter,
      AppSpace.lg,
    ),
  });

  final String title;

  /// The form, top to bottom, stretched to the page width.
  final List<Widget> fields;

  /// The page's one primary action. Null when the page has none right now (a
  /// stage whose action is a tap in the body); the bar then shows only
  /// [secondary] and [status], or nothing.
  final EditorSave? save;

  /// A second, lesser action placed in the bar at the start (Delete).
  final Widget? secondary;

  /// A line in the bar above the actions: a summary of what Save will do, or
  /// a failure the person must see without scrolling.
  final Widget? status;

  /// App bar actions (help, overflow). Never a second Save.
  final List<Widget> actions;

  /// Replaces the fields and the bar while the form cannot be shown: loading,
  /// or a failed read with its retry.
  final Widget? placeholder;

  /// Around the fields.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final placeholder = this.placeholder;
    final hasBar =
        placeholder == null &&
        (save != null || secondary != null || status != null);
    // The title is said in full at the top of the form, where it wraps; the
    // bar repeats it once that heading has scrolled away (TO-12).
    return PageTitleScope(
      child: Scaffold(
        appBar: AppBar(
          leading: (route?.impliesAppBarDismissal ?? false)
              ? const CloseButton()
              : null,
          title: PageBarTitle(title),
          actions: actions,
        ),
        body: PageBody(
          child: SafeArea(
            top: false,
            bottom: !hasBar,
            child:
                placeholder ??
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: padding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PageHeader(
                              title: title,
                              padding: const EdgeInsets.only(
                                bottom: AppSpace.sm,
                              ),
                            ),
                            ...fields,
                          ],
                        ),
                      ),
                    ),
                    if (hasBar)
                      EditorActionBar(
                        save: save,
                        secondary: secondary,
                        status: status,
                      ),
                  ],
                ),
          ),
        ),
      ),
    );
  }
}

/// [EditorPage]'s pinned bar, on its own so a page that cannot be an
/// [EditorPage] yet (a map editor) pins the same bar.
class EditorActionBar extends StatelessWidget {
  const EditorActionBar({super.key, this.save, this.secondary, this.status});

  final EditorSave? save;
  final Widget? secondary;
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final save = this.save;
    final secondary = this.secondary;
    final status = this.status;
    final Widget? button = save == null ? null : _SaveButton(save: save);
    final Widget? row = switch ((secondary, button)) {
      (null, null) => null,
      (final s?, null) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: s,
      ),
      (null, final b?) => b,
      (final s?, final b?) => OverflowBar(
        alignment: MainAxisAlignment.spaceBetween,
        overflowAlignment: OverflowBarAlignment.end,
        spacing: AppSpace.sm,
        overflowSpacing: AppSpace.sm,
        children: [s, b],
      ),
    };
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppInsets.gutter,
              AppSpace.smPlus,
              AppInsets.gutter,
              AppSpace.smPlus,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (status != null)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: row == null ? 0 : AppSpace.sm,
                    ),
                    child: status,
                  ),
                if (row != null) row,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.save});

  final EditorSave save;

  @override
  Widget build(BuildContext context) {
    final label = Text(save.label, textAlign: TextAlign.center);
    return FilledButton(
      key: save.key,
      onPressed: save.busy ? null : save.onPressed,
      child: save.busy
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpace.sm),
                Flexible(child: label),
              ],
            )
          : label,
    );
  }
}
