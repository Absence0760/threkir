import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show EditorPage, EditorSave;

import 'confirm_discard.dart';

export 'package:ui_kit/ui_kit.dart' show EditorSave;

/// Canonical presentation for a create / edit entity form on mobile: a
/// full-screen modal dialog (slide-up, close affordance) whose page is
/// ui_kit's [EditorPage], laid out by the [FullScreenFormBody] that [builder]
/// returns.
///
/// Every "add / edit X" sheet routes through here (gear, club, event,
/// challenge, goal, gym, routine, nutrition, plate photo, planned-workout
/// edit), so the presentation is identical and no form re-derives the
/// wrapper. A full-page editor pushed as an ordinary route builds the same
/// [EditorPage] itself under a [DiscardGuard].
///
/// [title] is read from the caller's context once (the heading lives in the
/// app bar, not inline in the body). Resolves to whatever the form pops.
///
/// [isDirty], when set, arms a [DiscardGuard]: backing out (system back, the
/// close button, or any `maybePop`) while it reports unsaved edits confirms
/// via [confirmDiscard] before popping. Save paths that pop with
/// `Navigator.pop` after persisting bypass the guard by design. [isBusy]
/// refuses the pop while a save is in flight.
Future<T?> showFullScreenForm<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  bool Function()? isDirty,
  bool Function()? isBusy,
}) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      fullscreenDialog: true,
      builder: (ctx) {
        final page = _FormTitle(
          title: title,
          child: Builder(builder: builder),
        );
        if (isDirty == null && isBusy == null) return page;
        return DiscardGuard(
          isDirty: isDirty ?? () => false,
          isBusy: isBusy,
          child: page,
        );
      },
    ),
  );
}

class _FormTitle extends InheritedWidget {
  const _FormTitle({required this.title, required super.child});

  final String title;

  @override
  bool updateShouldNotify(_FormTitle old) => old.title != title;
}

/// The page of a [showFullScreenForm] form: its fields in [children], its one
/// primary action in [save], pinned above the keyboard and the nav bar by
/// [EditorPage]. There is no Cancel; the app bar's close button is the way
/// out, through the discard guard.
class FullScreenFormBody extends StatelessWidget {
  const FullScreenFormBody({
    super.key,
    required this.children,
    this.save,
    this.secondary,
    this.status,
  });

  final List<Widget> children;

  /// See [EditorPage.save].
  final EditorSave? save;

  /// See [EditorPage.secondary].
  final Widget? secondary;

  /// See [EditorPage.status].
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    // Outside showFullScreenForm (a widget test mounting the form alone)
    // there is no title to show.
    final scope = context.dependOnInheritedWidgetOfExactType<_FormTitle>();
    return EditorPage(
      title: scope?.title ?? '',
      fields: children,
      save: save,
      secondary: secondary,
      status: status,
    );
  }
}
